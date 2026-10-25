#!/usr/bin/env python3
"""A long-running local session of one addon, served to the browser viewer.

    python tools/session.py <addon-dir> [--flavor F|auto] [--size WxH] [--port N] [--bind 127.0.0.1]
                            [--extract DIR] [--bindings FILE] [--no-watch]
    python tools/session.py --selftest

Prints `session: http://127.0.0.1:<port>/` and serves until Ctrl-C (exit 0). Exit 2 on a usage error or a --bind
that is not 127.0.0.1: the session answers only the local machine. --no-watch is accepted now; the file watcher that
reloads on a save arrives with live reload.
"""

import argparse
import os
import sys
import time
from pathlib import Path

LOOPBACK = "127.0.0.1"
FLAVORS = ("auto", "retail", "mists", "vanilla", "tbc", "forever")
DEFAULT_SIZE = (1920, 1080)
VIEWER_DIR = Path(__file__).resolve().parent.parent / "viewer"


class Running:
    """A started session: .port, .url and .stop()."""

    def __init__(self, server, host, bus, thread):
        self.server, self.host, self.bus, self.thread = server, host, bus, thread
        self.port = server.server_address[1]
        self.url = f"http://{LOOPBACK}:{self.port}/"

    def stop(self):
        self.bus.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.host.shutdown()


def start(addon_dir, port=0, flavor="retail", size=DEFAULT_SIZE, watch=False, extract=None, bindings=None):
    """Loads the addon, starts serving on 127.0.0.1:port (0 picks a free port) and returns the Running session.

    watch is accepted for the CLI's --no-watch; nothing watches files yet.
    """
    import threading

    import session_host
    import session_http

    bus = session_http.Bus()
    host = session_host.LuaHost(bus, os.path.abspath(addon_dir), flavor, size, extract, bindings)
    try:
        server = session_http.Server(port, host, bus, VIEWER_DIR, host.assets_dir)
    except OSError:
        host.shutdown()
        raise
    thread = threading.Thread(target=server.serve_forever, name="session-http", daemon=True)
    thread.start()
    return Running(server, host, bus, thread)


def _size(text):
    import preview

    size = preview.parse_size(text)
    if size is None:
        raise argparse.ArgumentTypeError(f"expected WxH with both sides in 1..{preview.MAX_SIDE}, got {text!r}")
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
    return None


def wait_for_interrupt(running):
    """Blocks until Ctrl-C."""
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
        running = start(args.addon_dir, args.port, args.flavor, args.size, not args.no_watch, args.extract, args.bindings)
    except OSError as err:
        return _usage_error(f"cannot listen on {LOOPBACK}:{args.port}: {err.strerror or err}")
    print(f"session: {running.url}", flush=True)
    try:
        wait(running)
    finally:
        running.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
