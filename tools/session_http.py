"""HTTP face of a session: a loopback-only server that relays JSON to a LuaHost and streams its events.

    GET  /snapshot           the render snapshot with assets resolved
    GET  /tree               the inspector's widget tree: { ok, nodes }
    GET  /frame?id=<id>      one widget's properties: { ok, props }, or 404 { ok: false } for an unknown id
    GET  /events             the flavor's events with their payload parameters: { ok, events }
    GET  /state              the mock state: { ok, state }
    GET  /dev                the developer report: { ok, addons, notes } (POST to /tree, /events or /dev is 405)
    POST /call/<method>      any method, through SessionHost:handleJson; the reply is always status 200
    POST /input /fire /slash /state /reload   the same calls for curl and the selftests (400 when the request is malformed)
                             (/reload takes { flavor?, size?, keepSaved? }; session_options.lua checks it, 400 if bad)
    GET  /stream             server-sent events: snapshot, console, reload (a keepalive comment every 15 s)
    GET  /                   redirects to the live viewer, fitted to the window; /viewer/* and /assets/* are static files

Every request is checked before it is routed: the Host header must name this server, a request with an Origin must come
from this server's own page, and a POST must carry Content-Type: application/json.
"""

import json
import os
import queue
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

KEEPALIVE_SECONDS = 15
MAX_BODY = 1 << 20
QUEUE_SIZE = 256
CALL_PATH = re.compile(r"^/call/([a-z]+)$")
READ_ONLY = ("/tree", "/events", "/dev")
REST_METHODS = {"/input": "input", "/fire": "fire", "/slash": "slash", "/state": "state", "/reload": "reload"}
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
}


class Subscriber:
    """One /stream client: a bounded queue; a client that falls 256 events behind is dropped."""

    def __init__(self):
        self.q = queue.Queue(maxsize=QUEUE_SIZE)
        self.dead = False


class Bus:
    """Fan-out of (event, data) to every /stream client."""

    def __init__(self):
        self.lock = threading.Lock()
        self.subscribers = []

    def subscribe(self):
        sub = Subscriber()
        with self.lock:
            self.subscribers.append(sub)
        return sub

    def unsubscribe(self, sub):
        with self.lock:
            if sub in self.subscribers:
                self.subscribers.remove(sub)

    def publish(self, event, data):
        with self.lock:
            for sub in list(self.subscribers):
                try:
                    sub.q.put_nowait((event, data))
                except queue.Full:
                    sub.dead = True
                    self.subscribers.remove(sub)

    def close(self):
        """Wakes every /stream handler so it ends."""
        with self.lock:
            for sub in self.subscribers:
                sub.dead = True
                try:
                    sub.q.put_nowait(None)
                except queue.Full:
                    pass
            self.subscribers.clear()


def _static_file(root, relative):
    """The file under root that the url remainder names, or None unless its real path stays inside root."""
    relative = unquote(relative)
    if not relative or "\0" in relative or ":" in relative:
        return None
    real_root = os.path.realpath(root)
    target = os.path.realpath(os.path.join(real_root, relative))
    try:
        inside = os.path.commonpath([real_root, target]) == real_root
    except ValueError:  # another drive
        return None
    return Path(target) if inside and os.path.isfile(target) else None


class Handler(BaseHTTPRequestHandler):
    """server.host is the LuaHost, server.bus the Bus, server.viewer_dir and server.assets_dir the static roots."""

    server_version = "wow-testkit-session"

    def log_message(self, format, *args):  # noqa: A002  (the base class's name)
        pass

    # Replies ---------------------------------------------------------------------------------------------------

    def _send(self, status, body, content_type, headers=()):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, status, payload):
        text = payload if isinstance(payload, str) else json.dumps(payload, separators=(",", ":"))
        self._send(status, text.encode("utf-8"), "application/json")

    def _refuse(self, status, message):
        self._send_json(status, {"ok": False, "error": message})

    # Checks ----------------------------------------------------------------------------------------------------

    def _guard(self, post=False):
        """True when the request may be routed; otherwise the refusal is already sent."""
        port = self.server.server_address[1]
        host = (self.headers.get("Host") or "").lower()
        if host not in (f"127.0.0.1:{port}", f"localhost:{port}"):
            self._refuse(403, "forbidden host")
            return False
        origin = self.headers.get("Origin")
        if origin is not None and origin.lower() != f"http://{host}":
            self._refuse(403, "forbidden origin")
            return False
        content_type = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if post and content_type != "application/json":
            self._refuse(415, "content type must be application/json")
            return False
        return True

    def _body(self):
        """The request body as text; '{}' when there is none. None after replying 400 or 413."""
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if length < 0:
            self._refuse(400, "malformed request: bad Content-Length")
            return None
        if length > MAX_BODY:
            self._refuse(413, "request body too large")
            return None
        return self.rfile.read(length).decode("utf-8", errors="replace").strip() or "{}"

    # Routes ----------------------------------------------------------------------------------------------------

    def do_GET(self):
        if not self._guard():
            return
        url = urlsplit(self.path)
        path = url.path
        if path == "/":
            self._send(302, b"", "text/plain", [("Location", "/viewer/index.html?live=1&zoom=fit")])
        elif path == "/snapshot":
            self._send_json(200, self.server.host.snapshot_json())
        elif path in READ_ONLY or path == "/state":
            self._send_json(200, self.server.host.call_json(path[1:], "{}"))
        elif path == "/frame":
            self._frame(parse_qs(url.query).get("id", [""])[0])
        elif path == "/stream":
            self._stream()
        elif path.startswith("/viewer/"):
            self._static(self.server.viewer_dir, path[len("/viewer/") :])
        elif path.startswith("/assets/"):
            self._static(self.server.assets_dir, path[len("/assets/") :])
        else:
            self._refuse(404, "not found")

    def do_POST(self):
        if not self._guard(post=True):
            return
        path = urlsplit(self.path).path
        call = CALL_PATH.match(path)
        if call:
            self._call(call.group(1))
        elif path in REST_METHODS:
            self._rest(REST_METHODS[path])
        elif path in READ_ONLY:
            self._send(405, b'{"ok": false, "error": "method not allowed"}', "application/json", [("Allow", "GET")])
        else:
            self._refuse(404, "not found")

    def _not_allowed(self):
        if self._guard():
            self._send(405, b'{"ok": false, "error": "method not allowed"}', "application/json", [("Allow", "GET, POST")])

    do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = _not_allowed

    def _call(self, method):
        text = self._body()
        if text is None:
            return
        if method == "snapshot":
            self._send_json(200, self.server.host.snapshot_json())
        else:
            self._send_json(200, self.server.host.call_json(method, text))

    def _rest(self, method):
        text = self._body()
        if text is None:
            return
        try:
            req = json.loads(text)
        except ValueError as err:
            self._refuse(400, f"malformed request: {err}")
            return
        if not isinstance(req, dict):
            self._refuse(400, "malformed request: expected a JSON object")
            return
        reply = self.server.host.call(method, req)
        self._send_json(400 if reply.get("ok") is False and "error" in reply else 200, reply)

    def _frame(self, frame_id):
        reply = self.server.host.call("frame", {"id": frame_id})
        self._send_json(200 if reply.get("ok") else 404, reply)

    def _static(self, root, relative):
        found = _static_file(root, relative)
        if found is None:
            self._refuse(404, "not found")
            return
        self._send(200, found.read_bytes(), CONTENT_TYPES.get(found.suffix.lower(), "application/octet-stream"))

    def _stream(self):
        bus = self.server.bus
        sub = bus.subscribe()
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(b": open\n\n")
            self.wfile.flush()
            while True:
                try:
                    item = sub.q.get(timeout=KEEPALIVE_SECONDS)
                except queue.Empty:
                    if sub.dead:
                        break
                    chunk = b": keepalive\n\n"
                else:
                    if item is None:
                        break
                    chunk = f"event: {item[0]}\ndata: {json.dumps(item[1])}\n\n".encode("utf-8")
                self.wfile.write(chunk)
                self.wfile.flush()
        except OSError:  # the client went away
            pass
        finally:
            bus.unsubscribe(sub)


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, port, host, bus, viewer_dir, assets_dir):
        super().__init__(("127.0.0.1", port), Handler)
        self.host, self.bus, self.viewer_dir, self.assets_dir = host, bus, viewer_dir, assets_dir
