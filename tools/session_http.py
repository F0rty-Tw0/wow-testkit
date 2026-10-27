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
    GET  /stream             server-sent events: hello { boot } first, then snapshot, console, reload, combatlog (a
                             keepalive comment every 15 s); boot is random per server, so a viewer can tell a restarted one
    GET  /?token=<token>     sets the session cookie and redirects to the live viewer, fitted to the window
    GET  /viewer/*, /assets/*   static files

Every request is checked before it is routed: the Host header must name this server, a request with an Origin must come
from this server's own page, and a POST must carry Content-Type: application/json. Every route but / and /viewer/* also
needs the session's token, from the cookie or an X-Session-Token header (401 otherwise); a GET whose query carries
token=<token> sets that cookie (HttpOnly, SameSite=Strict, named per port so two sessions keep their own). The token is
saved in the session folder, so a restarted server accepts the cookie its viewer holds. Every reply carries
Referrer-Policy: no-referrer. At most MAX_CONNECTIONS connections are served at once.
"""

import hmac
import json
import queue
import re
import secrets
import threading
from http.cookies import CookieError, SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

import session_files

KEEPALIVE_SECONDS = 15
# Connections served at once. timeout bounds one read, not a request, so a client that trickles a header line every few
# seconds holds its thread for as long as it likes; past this many, a new connection is closed unanswered.
MAX_CONNECTIONS = 32
MAX_BODY = 1 << 20
VIEWER_URL = "/viewer/index.html?live=1&zoom=fit"
CALL_PATH = re.compile(r"^/call/([a-z]+)$")
READ_ONLY = ("/tree", "/events", "/dev")
REST_METHODS = {"/input": "input", "/fire": "fire", "/slash": "slash", "/state": "state", "/reload": "reload"}


class Handler(BaseHTTPRequestHandler):
    """server.host is the LuaHost, server.bus the Bus, server.viewer_dir and server.assets_dir the static roots."""

    server_version = "wow-testkit-session"
    timeout = 30  # seconds a socket may stall before its handler gives up, so a silent client cannot hold a thread
    grant = False  # the request passed every check with the token in its query: the reply sets the session cookie

    def log_message(self, format, *args):  # noqa: A002  (the base class's name)
        pass

    def end_headers(self):
        """Every reply's headers end here, the base class's error replies too."""
        self.send_header("Referrer-Policy", "no-referrer")
        super().end_headers()

    # Replies ---------------------------------------------------------------------------------------------------

    def _send(self, status, body, content_type, headers=()):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for name, value in headers:
            self.send_header(name, value)
        if self.grant:
            self.send_header("Set-Cookie", f"{self._cookie_name()}={self.server.token}; HttpOnly; SameSite=Strict; Path=/")
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, status, payload):
        text = payload if isinstance(payload, str) else json.dumps(payload, separators=(",", ":"))
        self._send(status, text.encode("utf-8"), "application/json")

    def _refuse(self, status, message):
        self._send_json(status, {"ok": False, "error": message})

    # Checks ----------------------------------------------------------------------------------------------------

    def _cookie_name(self):
        return f"tk_session_{self.server.server_address[1]}"

    def _is_token(self, offered):
        return isinstance(offered, str) and hmac.compare_digest(offered.encode("utf-8"), self.server.token.encode("utf-8"))

    def _authorized(self):
        """True when the cookie or the X-Session-Token header carries the session's token."""
        try:
            morsel = SimpleCookie(self.headers.get("Cookie") or "").get(self._cookie_name())
        except CookieError:
            morsel = None
        return self._is_token(self.headers.get("X-Session-Token")) or bool(morsel and self._is_token(morsel.value))

    def _problem(self, post):
        """(status, message) of the first check the request fails, or None. A request that passes them all with the
        token in its query sets grant, so no refusal sets the cookie."""
        url = urlsplit(self.path)
        offered = parse_qs(url.query).get("token", [None])[0]
        granting = not post and self._is_token(offered)
        port = self.server.server_address[1]
        host = (self.headers.get("Host") or "").lower()
        if host not in (f"127.0.0.1:{port}", f"localhost:{port}"):
            return 403, "forbidden host"
        origin = self.headers.get("Origin")
        if origin is not None and origin.lower() != f"http://{host}":
            return 403, "forbidden origin"
        content_type = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if post and content_type != "application/json":
            return 415, "content type must be application/json"
        if not (url.path.startswith("/viewer/") or granting or self._authorized()):
            return 401, "no session token: open the URL session.py printed"
        self.grant = granting

        return None

    def _guard(self, post=False):
        """True when the request may be routed; otherwise the refusal is already sent.

        A refused request's body is read first: closing a socket with unread data resets the connection, and the
        client can lose the reply.
        """
        problem = self._problem(post)
        if problem is None:
            return True
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if 0 < length <= MAX_BODY:
            self.rfile.read(length)
        self._refuse(*problem)

        return False

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
            self._send(302, b"", "text/plain", [("Location", VIEWER_URL)])
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
        except (ValueError, RecursionError) as err:  # RecursionError: nested deeper than Python's parser goes
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
        found = session_files.static_file(root, relative)
        if found is None:
            self._refuse(404, "not found")
            return
        self._send(200, found.read_bytes(), session_files.content_type(found))

    def _stream(self):
        bus = self.server.bus
        sub = bus.subscribe()
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            hello = json.dumps({"boot": self.server.boot})
            self.wfile.write(f"event: hello\ndata: {hello}\n\n".encode("utf-8"))
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

    def __init__(self, port, host, bus, viewer_dir, assets_dir, token):
        super().__init__(("127.0.0.1", port), Handler)
        self.host, self.bus, self.viewer_dir, self.assets_dir = host, bus, viewer_dir, assets_dir
        self.token = token
        self.boot = secrets.token_hex(8)
        self.slots = threading.BoundedSemaphore(MAX_CONNECTIONS)

    def process_request(self, request, client_address):
        """Serves the connection on a new thread while a slot is free; closes it unanswered otherwise."""
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()
