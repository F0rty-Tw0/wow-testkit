#!/usr/bin/env python3
"""A long-running local session of one addon, served to the browser viewer.

    python tools/session.py <addon-dir> [--flavor F|auto] [--size WxH|1080p|1440p|4k] [--port N] [--bind 127.0.0.1]
                            [--extract DIR] [--bindings FILE] [--no-watch] [--blizzard-ui]
                            [--wtf DIR [--wtf-account NAME] [--wtf-character REALM/CHARACTER]]
    python tools/session.py --selftest

Prints `session: http://127.0.0.1:<port>/?token=<token>` (the token every request but the viewer's files needs, kept
in the session folder for a day so a restart on the same addon accepts the viewer's cookie) and serves until Ctrl-C (exit 0).
Exit 2 on a usage error or a --bind that is not 127.0.0.1: the session answers only the local machine. A save of a
.lua, .xml or .toc file, or of an image or font, under the addon folder reloads the addon (--no-watch turns that off; a failed reload prints on
stderr); SavedVariables are written at a reload and at shutdown. --wtf reads a client's WTF folder (never writes it):
its CVars, key bindings and Edit Mode layouts go in before each login, and its SavedVariables seed a session that has
none yet.
"""

import argparse
import atexit
import os
import signal
import sys
import time
from pathlib import Path

LOOPBACK = "127.0.0.1"
FLAVORS = ("auto", "retail", "mists", "vanilla", "tbc", "forever")
DEFAULT_SIZE = (1920, 1080)
SIZE_PRESETS = {"1080p": (1920, 1080), "1440p": (2560, 1440), "4k": (3840, 2160)}
MIN_SIZE, MAX_SIZE = (320, 240), (7680, 4320)
VIEWER_DIR = Path(__file__).resolve().parent.parent / "viewer"


class Running:
    """A started session: .port, .token, .url (which carries the token) and .stop() (safe to call twice)."""

    def __init__(self, server, host, bus, thread, watcher=None):
        self.server, self.host, self.bus, self.thread, self.watcher = server, host, bus, thread, watcher
        self.port, self.token = server.server_address[1], server.token
        self.url = f"http://{LOOPBACK}:{self.port}/?token={self.token}"
        self.stopped = False

    def stop(self):
        if self.stopped:
            return
        self.stopped = True
        if self.watcher:
            self.watcher.stop()
        self.bus.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.host.shutdown()


def start(addon_dir, port=0, flavor="retail", size=DEFAULT_SIZE, watch=False, extract=None, bindings=None, blizzard_ui=False, wtf=None):
    """Loads the addon, starts serving on 127.0.0.1:port (0 picks a free port) and returns the Running session.

    With blizzard_ui, Blizzard's own UI addons from the extract load before the addon (blizzard_ui.lua).

    wtf is {"dir", "account"?, "character"?} or a WTF folder path (session_wtf.lua imports it, read only).

    With watch, a save under addon_dir reloads the addon through the host; a reload that fails is reported on stderr.
    """
    import threading

    import session_bus
    import session_files
    import session_host
    import session_http
    import session_watch

    bus = session_bus.Bus()
    wtf = {"dir": wtf} if isinstance(wtf, str) else wtf
    host = session_host.LuaHost(bus, os.path.abspath(addon_dir), flavor, size, extract, bindings, blizzard_ui=blizzard_ui, wtf=wtf)
    try:
        token = session_files.session_token(host.session_dir)
        server = session_http.Server(port, host, bus, VIEWER_DIR, host.assets_dir, token)
    except OSError:
        host.shutdown()
        raise
    thread = threading.Thread(target=server.serve_forever, name="session-http", daemon=True)
    thread.start()
    watcher = session_watch.Watcher(os.path.abspath(addon_dir), lambda: _report_reload(host.call("reload", {}))) if watch else None
    if watcher:
        watcher.start()
    return Running(server, host, bus, thread, watcher)


def _report_reload(reply):
    if not reply.get("ok"):
        print(f"reload failed: {reply.get('error')}", file=sys.stderr, flush=True)


def _size(text):
    """A preset name or WxH, in the range a reload accepts (session_options.lua PRESETS and MIN/MAX sides)."""
    import preview

    size = SIZE_PRESETS.get(text) or preview.parse_size(text)
    fits = size and MIN_SIZE[0] <= size[0] <= MAX_SIZE[0] and MIN_SIZE[1] <= size[1] <= MAX_SIZE[1]
    if not fits:
        raise argparse.ArgumentTypeError(f"expected 1080p, 1440p, 4k or WxH within 320x240 to 7680x4320, got {text!r}")
    return size


def _parser():
    parser = argparse.ArgumentParser(prog="session.py", description="Serve a live session of one addon to the browser viewer.")
    parser.add_argument("addon_dir")
    parser.add_argument("--flavor", choices=FLAVORS, default="auto")
    parser.add_argument("--size", type=_size, default=DEFAULT_SIZE, metavar="WxH")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--bind", default=LOOPBACK)
    parser.add_argument("--extract", metavar="DIR")
    parser.add_argument("--bindings", metavar="FILE")
    parser.add_argument("--no-watch", action="store_true")
    parser.add_argument("--blizzard-ui", action="store_true")
    parser.add_argument("--wtf", metavar="DIR")
    parser.add_argument("--wtf-account", metavar="NAME")
    parser.add_argument("--wtf-character", metavar="REALM/CHARACTER")
    return parser


def _usage_error(text):
    print(f"error: {text}", file=sys.stderr)
    return 2


def _check(args):
    """A usage-error message for args, or None."""
    if args.bind != LOOPBACK:
        return f"--bind must be {LOOPBACK}: the session serves only the local machine"
    if not 0 <= args.port <= 65535:
        return f"--port must be 0..65535, got {args.port}"
    if not os.path.isdir(args.addon_dir):
        return f"no such directory: {args.addon_dir}"
    if args.extract and not os.path.isdir(args.extract):
        return f"no such directory: {args.extract}"
    if args.bindings and not os.path.isfile(args.bindings):
        return f"no such file: {args.bindings}"
    if args.blizzard_ui and not args.extract:
        return "--blizzard-ui needs --extract: the Blizzard UI addons come from the client extract"
    return _check_wtf(args)


def _check_wtf(args):
    if args.wtf and not os.path.isdir(args.wtf):
        return f"--wtf: no such directory: {args.wtf}"
    if (args.wtf_account or args.wtf_character) and not args.wtf:
        return "--wtf-account needs --wtf" if args.wtf_account else "--wtf-character needs --wtf"
    if args.wtf_character and "/" not in args.wtf_character.strip("/"):
        return "--wtf-character must be REALM/CHARACTER"
    return None


def _terminate(signum, frame):
    raise KeyboardInterrupt


def wait_for_interrupt(running):
    """Blocks until Ctrl-C or SIGTERM."""
    signal.signal(signal.SIGTERM, _terminate)
    try:
        while True:
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass


def main(argv, wait=wait_for_interrupt):
    """Runs the CLI; wait(running) blocks while the session serves (tests pass a function that returns)."""
    if argv == ["--selftest"]:
        import session_selftest

        return session_selftest.run()
    try:
        args = _parser().parse_args(argv)
    except SystemExit as done:
        return done.code if isinstance(done.code, int) else 2
    problem = _check(args)
    if problem:
        return _usage_error(problem)
    try:
        wtf = {"dir": args.wtf, "account": args.wtf_account, "character": args.wtf_character} if args.wtf else None
        running = start(args.addon_dir, args.port, args.flavor, args.size, not args.no_watch, args.extract, args.bindings, args.blizzard_ui, wtf)
    except OSError as err:
        return _usage_error(f"cannot listen on {LOOPBACK}:{args.port}: {err.strerror or err}")
    print(f"session: {running.url}", flush=True)
    atexit.register(running.stop)
    try:
        wait(running)
    finally:
        running.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
