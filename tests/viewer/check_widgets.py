#!/usr/bin/env python3
"""DOM assertions for the viewer widget check (tests/viewer/widgets_check.sh) on widgets_fixture.json.

    python tests/viewer/check_widgets.py <dom.html>

Prints PASS/FAIL per check and a count; exit 1 on any failure.
"""

import sys

from dom_tree import TreeParser, by_class, by_id, expect_style, one


def check_selection(root):
    box = by_id(root, "f1")
    selected = one(box, by_class("selection"), ".selection")
    if selected.text() != "el":
        raise AssertionError(".selection %r, want 'el'" % selected.text())
    around = one(box, by_class("text"), ".text").texts
    if around != ["h", "lo"]:
        raise AssertionError("text around the selection %s, want ['h', 'lo']" % around)


def check_reversed_fill(root):
    fill = one(by_id(root, "f2"), by_class("fill"), ".fill")
    # Chrome serialises top, right, bottom and left as the inset shorthand: top 0, right 0, bottom auto, left auto.
    expect_style(fill, {"inset": "0px 0px auto auto", "width": "80%"})


def check_center_fill(root):
    fill = one(by_id(root, "f4"), by_class("fill"), ".fill")
    expect_style(fill, {"inset": "0px auto auto 25%", "width": "50%", "height": "100%"})
    vertical = one(by_id(root, "f6"), by_class("fill"), ".fill")
    expect_style(vertical, {"inset": "40% auto auto 0px", "width": "100%", "height": "20%"})


def check_reverse_fill_style(root):
    fill = one(by_id(root, "f5"), by_class("fill"), ".fill")
    expect_style(fill, {"inset": "0px 0px auto auto", "width": "80%"})


def check_thumb(root):
    thumb = one(by_id(root, "f3"), by_class("thumb"), ".thumb")
    expect_style(thumb, {"left": "50%", "width": "10px", "height": "20px", "background-color": "rgb(255, 0, 0)"})
    if "translate(-50%, -50%)" not in thumb.style().get("transform", ""):
        raise AssertionError("transform %r" % thumb.style().get("transform"))


CHECKS = [
    ("edit selection", check_selection),
    ("reversed status bar fill", check_reversed_fill),
    ("centre status bar fill", check_center_fill),
    ("reverse fill style status bar", check_reverse_fill_style),
    ("slider thumb at the value fraction", check_thumb),
]


def main(argv):
    if len(argv) != 2:
        print("usage: check_widgets.py <dom.html>")
        return 2
    parser = TreeParser()
    with open(argv[1], encoding="utf-8", errors="replace") as handle:
        parser.feed(handle.read())
    failed = 0
    for name, check in CHECKS:
        try:
            check(parser.root)
            print("PASS " + name)
        except AssertionError as err:
            failed += 1
            print("FAIL %s: %s" % (name, err))
    print("%d passed, %d failed" % (len(CHECKS) - failed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
