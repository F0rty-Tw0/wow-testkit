#!/usr/bin/env python3
"""Compares the Python-side and the browser-side parity runs (tests/wasm/parity.sh).

    python tests/wasm/compare_parity.py <side_a.json> <side_b.html>
    python tests/wasm/compare_parity.py --self-check <side_a.json>

Both sides are [{ method, reply, events }]: side A from SessionHost under lupa (parity_side_a.lua), side B from the
<pre id="out"> of the page the worker ran in (parity_page.js). Entry 0 of side A also carries the kit root and the
session folder it ran in. Both sides are masked, then compared as JSON, step by step:
  1. dev replies: loadMs and memoryKb -> 0
  2. in every string: <repo>/tests/fixtures/addons/ and /addon/ -> ADDON/, then @<repo>/ and @/kit/ -> @KIT/, then
     <repo>/ and /kit/ -> KIT/, then the session folder -> SESSION (side A's temp folder, side B's /session/...)
  3. in a traceback (a string with "stack traceback:"): a backslash in a kit file name becomes / (lupa on
     Windows joins the dots of require("framexml.fakes.slash") with the OS separator, the browser and Linux use /);
     and the lines after the "..." Lua puts in the middle of a deep traceback go, because they are the last frames of
     whatever drives the host (tests/run.lua and parity_side_a.lua here, the C bootstrap on side B), not kit frames
Prints PASS step <i> <method> or FAIL step <i> <method>: <first differing JSON path>, then "N passed, M failed". Exit 1
on any failure. --self-check changes step 3 of side A and prints PASS self-check when that is reported as a failure.
"""

import copy
import json
import os
import re
import sys
from html.parser import HTMLParser

SESSION_B = "/session/_none/_account/SessionDemo"
DEFAULT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))).replace("\\", "/")


class OutParser(HTMLParser):
    """The text of <pre id="out">, and whether it carries data-done."""

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


def read_side_b(path):
    with open(path, encoding="utf-8") as handle:
        parser = OutParser()
        parser.feed(handle.read())
    if not parser.found or not parser.done:
        sys.exit('FAIL parity: side B never finished (no <pre id="out" data-done="1"> in ' + path + ")")
    try:
        return json.loads("".join(parser.text))
    except ValueError as err:
        sys.exit("FAIL parity: side B output is not JSON: " + str(err))


def mask_text(text, root, session):
    for old in (root + "/tests/fixtures/addons/", "/addon/"):
        text = text.replace(old, "ADDON/")
    for old in ("@" + root + "/", "@/kit/"):
        text = text.replace(old, "@KIT/")
    for old in (root + "/", "/kit/"):
        text = text.replace(old, "KIT/")
    text = text.replace(session, "SESSION") if session else text
    if "stack traceback:" in text:
        text = re.sub(r"KIT/[\w.\\/]+", lambda hit: hit.group().replace("\\", "/"), text)
        text = re.sub(r"\n\t\.\.\.\n.*\Z", "\n\t...", text, flags=re.S)
    return text


def mask_value(value, root, session):
    if isinstance(value, str):
        return mask_text(value, root, session)
    if isinstance(value, list):
        return [mask_value(item, root, session) for item in value]
    if isinstance(value, dict):
        return {key: mask_value(item, root, session) for key, item in value.items()}
    return value


def mask_entry(entry, root, session):
    out = {key: copy.deepcopy(entry.get(key)) for key in ("method", "reply", "events")}
    if out["method"] == "dev":
        for addon in out["reply"].get("addons", []):
            addon["loadMs"] = 0
            addon["memoryKb"] = 0
    return mask_value(out, root, session)


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def first_diff(a, b, path="$"):
    """The JSON path of the first difference between a and b, or None when equal. A bool is not a number."""
    if type(a) is not type(b) and not (is_number(a) and is_number(b)):
        return path
    if isinstance(a, dict):
        for key in sorted(set(a) | set(b)):
            if key not in a or key not in b:
                return path + "." + key
            found = first_diff(a[key], b[key], path + "." + key)
            if found:
                return found
        return None
    if isinstance(a, list):
        for index in range(max(len(a), len(b))):
            if index >= len(a) or index >= len(b):
                return "%s[%d]" % (path, index)
            found = first_diff(a[index], b[index], "%s[%d]" % (path, index))
            if found:
                return found
        return None
    return None if a == b else path


def compare(side_a, side_b):
    """Prints the verdict of every step; returns the number of failures."""
    root = side_a[0].get("root", DEFAULT_ROOT)
    session_a = side_a[0].get("sessionDir", "")
    steps = max(len(side_a), len(side_b))
    failed = 0
    for index in range(steps):
        if index >= len(side_a) or index >= len(side_b):
            print("FAIL step %d: only one side has it" % index)
            failed += 1
            continue
        left = mask_entry(side_a[index], root, session_a)
        right = mask_entry(side_b[index], root, SESSION_B)
        found = first_diff(left, right)
        if found:
            print("FAIL step %d %s: %s" % (index, left["method"], found))
            failed += 1
        else:
            print("PASS step %d %s" % (index, left["method"]))
    print("%d passed, %d failed" % (steps - failed, failed))
    return failed


def main(argv):
    if argv[:1] == ["--self-check"]:
        with open(argv[1], encoding="utf-8") as handle:
            side_a = json.load(handle)
        other = copy.deepcopy(side_a)
        other[3]["reply"] = {"ok": False, "error": "self-check"}
        failed = compare(side_a, other)
        print("PASS self-check" if failed else "FAIL self-check: a changed step 3 went unnoticed")
        return 0 if failed else 1
    with open(argv[0], encoding="utf-8") as handle:
        side_a = json.load(handle)
    return 1 if compare(side_a, read_side_b(argv[1])) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
