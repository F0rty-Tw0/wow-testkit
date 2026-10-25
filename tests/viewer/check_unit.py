#!/usr/bin/env python3
"""Reads the DOM dumped from tests/viewer/unit.html and reports its PASS/FAIL lines.

    python tests/viewer/check_unit.py <dom.html>

Prints the lines of <pre id="out">, then "N passed, M failed". Exit 1 on any failure, on zero tests, or when the
harness never set data-done.
"""

import sys
from html.parser import HTMLParser


class OutParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.depth = 0
        self.found = False
        self.done = False
        self.text = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get("id") == "out" and not self.found:
            self.found = True
            self.depth = 1
            self.done = attrs.get("data-done") == "1"
        elif self.depth:
            self.depth += 1

    def handle_endtag(self, tag):
        if self.depth:
            self.depth -= 1

    def handle_data(self, data):
        if self.depth:
            self.text.append(data)


def main(path):
    with open(path, encoding="utf-8") as handle:
        parser = OutParser()
        parser.feed(handle.read())
    lines = [line for line in "".join(parser.text).splitlines() if line.startswith(("PASS ", "FAIL "))]
    passed = sum(line.startswith("PASS ") for line in lines)
    failed = len(lines) - passed
    for line in lines:
        print(line)
    print("%d passed, %d failed" % (passed, failed))
    if not parser.found or not parser.done:
        print("FAIL harness: #out missing data-done=1")
        return 1
    if not lines:
        print("FAIL harness: zero tests")
        return 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
