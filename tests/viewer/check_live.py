#!/usr/bin/env python3
"""DOM assertions for the live viewer (tests/viewer/live_check.sh) on the SessionDemo session.

    python tests/viewer/check_live.py <live.html>

Prints PASS/FAIL per numbered check; exit 1 on any failure. Later tasks append checks.
"""

import sys

from dom_tree import TreeParser, one


def check_ready(root):
    html = one(root, lambda n: n.tag == "html", "html")
    if html.attrs.get("data-ready") != "1":
        raise AssertionError("data-ready=%r" % html.attrs.get("data-ready"))
    one(root, lambda n: n.attrs.get("data-name") == "SessionDemoFrame", "[data-name=SessionDemoFrame]")


def check_hover(root):
    hover = one(root, lambda n: n.attrs.get("id") == "hover", "#hover")
    if "hidden" not in hover.attrs:
        raise AssertionError("#hover is shown")


CHECKS = [
    ("ready flag, live snapshot drawn", check_ready),
    ("hover outline hidden", check_hover),
]


def main(argv):
    if len(argv) != 2:
        print("usage: check_live.py <live.html>")
        return 2
    parser = TreeParser()
    with open(argv[1], encoding="utf-8", errors="replace") as handle:
        parser.feed(handle.read())
    failed = 0
    for number, (name, check) in enumerate(CHECKS, 1):
        try:
            check(parser.root)
            print("PASS %s (%d)" % (name, number))
        except AssertionError as err:
            failed += 1
            print("FAIL %s (%d): %s" % (name, number, err))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
