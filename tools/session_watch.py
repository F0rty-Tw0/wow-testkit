"""Polls an addon folder for edits so a live session can reload on a save. Stdlib only."""

import os
import threading
import time

WATCHED = (".lua", ".xml", ".toc")


class Watcher:
    """Watcher(root, on_change, interval=0.5, quiet=0.3): calls on_change() once after the .lua, .xml and .toc files
    under root (dot-directories skipped) have stopped changing for `quiet` seconds. start() / stop()."""

    def __init__(self, root, on_change, interval=0.5, quiet=0.3):
        self.root, self.on_change, self.interval, self.quiet = root, on_change, interval, quiet
        self._stop = threading.Event()
        self._thread = None

    def _scan(self):
        """{path: (mtime_ns, size)} of the watched files; a file that vanishes mid-scan is left out."""
        seen = {}
        for folder, subdirs, names in os.walk(self.root):
            subdirs[:] = [d for d in subdirs if not d.startswith(".")]
            for name in names:
                if name.lower().endswith(WATCHED):
                    path = os.path.join(folder, name)
                    try:
                        stat = os.stat(path)
                    except OSError:
                        continue
                    seen[path] = (stat.st_mtime_ns, stat.st_size)
        return seen

    def _run(self):
        seen, changed_at = self._scan(), None
        while not self._stop.wait(self.interval):
            now = self._scan()
            if now != seen:
                seen, changed_at = now, time.monotonic()
            elif changed_at is not None and time.monotonic() - changed_at >= self.quiet:
                changed_at = None
                try:
                    self.on_change()
                except Exception as err:  # a failed reload must not end the watching
                    print(f"watch: reload failed: {err}", flush=True)

    def start(self):
        self._thread = threading.Thread(target=self._run, name="session-watch", daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=5)
