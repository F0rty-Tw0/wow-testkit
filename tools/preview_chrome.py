"""PNG of a render snapshot: serves the viewer and the output directory on 127.0.0.1, shoots the page with headless Chrome.

Used through `python tools/preview.py png <out-dir> <png-file>`. Only viewer/, the output directory's snapshot.json and
its assets/ are reachable (`..` refused, one Host check against DNS rebinding), and the server stops on every exit path. Chrome always runs
with a private profile so it never attaches to the user's own browser.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

EXIT_OK, EXIT_USAGE, EXIT_NO_PNG = 0, 2, 3

VIEWER_DIR = Path(__file__).resolve().parent.parent / "viewer"
VIEWER_PREFIX = "/viewer/"
SNAPSHOT_NAME = "snapshot.json"
ASSETS_DIR = "assets"
WINDOWS_CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PATH_NAMES = ("chrome", "google-chrome", "chromium")
CHROME_TIMEOUT = 60
BUDGET_MS = 5000
HOST = "127.0.0.1"
PAGE = "/viewer/index.html?snapshot=/snapshot.json&bare=1"
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json",
    ".png": "image/png",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
}


def safe_file(root, rel):
    """The file under root named by the URL path `rel`, or None. Decodes once, then refuses `..`, drive and
    backslash tricks, anything that resolves outside root (symlinks included) and anything that is not a file."""
    parts = unquote(rel).split("/")
    if any(p == ".." or "\\" in p or ":" in p or "\0" in p for p in parts):
        return None
    root_real = os.path.realpath(root)
    target = os.path.realpath(os.path.join(root_real, *[p for p in parts if p not in ("", ".")]))
    try:
        inside = os.path.commonpath([root_real, target]) == root_real
    except ValueError:
        return None
    return target if inside and os.path.isfile(target) else None


def out_file(out_dir, rel):
    """The file the page may read from the output directory: snapshot.json or something under assets/. Nothing else
    there (the log, a previous run's files, whatever the user keeps beside them) is served."""
    if rel == SNAPSHOT_NAME:
        return safe_file(out_dir, rel)
    if rel.startswith(ASSETS_DIR + "/"):
        return safe_file(os.path.join(out_dir, ASSETS_DIR), rel[len(ASSETS_DIR) + 1 :])
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def host_allowed(self):
        port = self.server.server_address[1]
        return self.headers.get("Host") in (f"{HOST}:{port}", f"localhost:{port}")

    def target(self):
        raw = self.path
        if not raw.startswith("/") or raw.startswith("//"):
            return None
        path = urlsplit(raw).path
        if path.startswith(VIEWER_PREFIX):
            return safe_file(VIEWER_DIR, path[len(VIEWER_PREFIX) :])
        return out_file(self.server.out_dir, path[1:])

    def reply(self, send_body):
        if not self.host_allowed():
            return self.send_error(403)
        target = self.target()
        if target is None:
            return self.send_error(404)
        body = Path(target).read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPES.get(Path(target).suffix.lower(), "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def do_GET(self):
        self.reply(True)

    def do_HEAD(self):
        self.reply(False)


def start_server(out_dir):
    """Serves viewer/ at /viewer/ and out_dir's snapshot.json and assets/ at / on a random port of 127.0.0.1; the
    server runs on a thread."""
    server = ThreadingHTTPServer((HOST, 0), Handler)
    server.daemon_threads = True
    server.out_dir = str(out_dir)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def stop_server(server):
    server.shutdown()
    server.server_close()


def chrome_args(url, png, width, height, profile):
    """Chrome's arguments (without the executable); the private `profile` keeps headless Chrome away from the
    user's running browser."""
    return [
        "--headless=new",
        "--disable-gpu",
        f"--user-data-dir={profile}",
        "--hide-scrollbars",
        f"--window-size={width},{height}",
        f"--virtual-time-budget={BUDGET_MS}",
        f"--screenshot={png}",
        url,
    ]


def find_chrome(explicit=None):
    """--chrome, else $CHROME, else the Windows install, else chrome/google-chrome/chromium on PATH; a path that is
    not a file counts as missing. A PATH hit counts only as an absolute path: Windows searches the current directory
    first and answers `.\chrome.bat`, which could be shipped inside an addon. Never starts Chrome to ask: a bare launch
    can open a tab in the user's browser."""
    for candidate in (explicit, os.environ.get("CHROME"), WINDOWS_CHROME):
        if candidate and os.path.isfile(candidate):
            return candidate
        if explicit:
            return None
    for name in PATH_NAMES:
        found = shutil.which(name)
        if found and os.path.isabs(found):
            return found
    return None


def snapshot_size(out_dir):
    """(width, height) of the snapshot's screen; None when snapshot.json is missing or has no screen."""
    try:
        screen = json.loads((Path(out_dir) / "snapshot.json").read_text(encoding="utf-8"))["screen"]
        return int(screen["width"]), int(screen["height"])
    except (OSError, ValueError, KeyError, TypeError):
        return None


def taskkill_path():
    """Absolute path of taskkill: CreateProcess searches the current directory before System32, so a bare name could
    run a taskkill.exe shipped inside an addon."""
    return os.path.join(os.environ.get("SystemRoot") or r"C:\Windows", "System32", "taskkill.exe")


def kill_tree(proc):
    if sys.platform == "win32":
        subprocess.run([taskkill_path(), "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
    else:
        proc.kill()


def run_chrome(command):
    """Runs Chrome until it exits or CHROME_TIMEOUT passes (then its whole process tree dies); its output tail."""
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        output, _ = proc.communicate(timeout=CHROME_TIMEOUT)
    except subprocess.TimeoutExpired:
        kill_tree(proc)
        output, _ = proc.communicate()
        output += b"\nchrome timed out after %d s" % CHROME_TIMEOUT
    return output.decode("utf-8", "replace")[-2000:]


def shoot(chrome, out_dir, png_file, size, outline):
    """Serves, shoots, stops the server and removes the profile whatever happens. Exit code."""
    server, profile = start_server(out_dir), tempfile.mkdtemp(prefix="tk-preview-chrome-")
    try:
        url = f"http://{HOST}:{server.server_address[1]}{PAGE}" + ("&outline=1" if outline else "")
        args = chrome_args(url, png_file, size[0], size[1], profile)
        tail = run_chrome([chrome] + args)
    finally:
        stop_server(server)
        shutil.rmtree(profile, ignore_errors=True)
    if not os.path.isfile(png_file):
        print(f"error: Chrome wrote no PNG\n{tail}", file=sys.stderr)
        return EXIT_NO_PNG
    return EXIT_OK


def png(out_dir, png_file, size=None, chrome=None, outline=False):
    """Writes png_file: the viewer's picture of <out_dir>/snapshot.json. size defaults to the snapshot's screen.
    Exit 0; 2 for a png_file that does not end in .png (it is deleted first, so another kind of file would be lost) or
    without a readable snapshot; 3 when Chrome is missing or wrote no PNG."""
    if not str(png_file).lower().endswith(".png"):
        print(f"error: the picture must be a .png file, not {png_file}", file=sys.stderr)
        return EXIT_USAGE
    size = size or snapshot_size(out_dir)
    if size is None:
        print(f"error: no snapshot with a screen at {out_dir}/snapshot.json", file=sys.stderr)
        return EXIT_USAGE
    exe = find_chrome(chrome)
    if exe is None:
        print("error: Chrome not found; pass --chrome PATH or set CHROME", file=sys.stderr)
        return EXIT_NO_PNG
    png_file = os.path.abspath(png_file)
    os.makedirs(os.path.dirname(png_file), exist_ok=True)
    if os.path.exists(png_file):
        os.remove(png_file)
    return shoot(exe, out_dir, png_file, size, outline)
