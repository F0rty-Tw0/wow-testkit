#!/usr/bin/env python3
"""Checks that host/index.html carries the viewer page, so the viewer's scripts run there as they are.

    python tests/wasm/check_markup.py

Every <script src="X"> of viewer/index.html must appear in host/index.html as ../viewer/X, in the same order (the
host's own scripts may sit between them), every element id of viewer/index.html must exist in host/index.html, and in
both pages #background must sit inside #stage (so additive items blend with the scene). Prints "PASS markup" or
"FAIL markup: <what is missing>" and exits 0 or 1.
"""

import os
import sys
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


class Markup(HTMLParser):
    def __init__(self):
        super().__init__()
        self.scripts = []
        self.ids = set()
        self.parents = {}
        self.open = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get("id"):
            self.ids.add(attrs["id"])
            self.parents[attrs["id"]] = self.open[-1][1] if self.open else None
        if tag == "script" and attrs.get("src"):
            self.scripts.append(attrs["src"])
        if tag not in VOID_TAGS:
            self.open.append((tag, attrs.get("id")))

    def handle_endtag(self, tag):
        while self.open and self.open.pop()[0] != tag:
            pass


def parse(rel):
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        return None
    markup = Markup()
    with open(path, encoding="utf-8") as handle:
        markup.feed(handle.read())
    return markup


def missing_parts(viewer, host):
    """What of the viewer page host lacks: scripts out of order or absent, then ids."""
    wanted = ["../viewer/" + src for src in viewer.scripts]
    found = iter(host.scripts)
    out = ["script " + src for src in wanted if src not in found]
    out += ["id " + name for name in sorted(viewer.ids - host.ids)]
    for page, markup in (("viewer", viewer), ("host", host)):
        if markup.parents.get("background") != "stage":
            out.append(page + " #background outside #stage")
    return out


def main():
    viewer, host = parse("viewer/index.html"), parse("host/index.html")
    if host is None:
        print("FAIL markup: host/index.html missing")
        return 1
    missing = missing_parts(viewer, host)
    if missing:
        print("FAIL markup: " + ", ".join(missing))
        return 1
    print("PASS markup")
    return 0


if __name__ == "__main__":
    sys.exit(main())
