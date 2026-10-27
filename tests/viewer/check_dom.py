#!/usr/bin/env python3
"""DOM assertions for the viewer check (tests/viewer/check.sh) on the basic fixture.

    python tests/viewer/check_dom.py <dom.html>

Prints PASS/FAIL per check; exit 1 on any failure. The per-feature checks are in check_features.py.
"""

import sys

from check_features import CHECKS as FEATURE_CHECKS
from dom_tree import TreeParser, by_class, by_id, expect_style, find, one

ORDER = [
    "f1", "b1.center", "b1.edge", "t2", "t3", "t4", "s5", "s6", "t7", "f8", "f9", "s10",
    "t11", "t12", "t13", "t14", "t15", "t16", "t17", "t18", "f19", "b19.center", "f20", "b20.center", "f21", "b21.center", "f22", "b22.center",
    "s23", "s24", "s25", "s26", "s27", "s28", "s29", "s30", "s31", "t32",
]  # fmt: skip


def check_ready(root):
    html = one(root, lambda n: n.tag == "html", "html")
    if html.attrs.get("data-ready") != "1":
        raise AssertionError("data-ready=%r" % html.attrs.get("data-ready"))
    expect_style(one(root, lambda n: n.attrs.get("id") == "stage", "#stage"), {"width": "400px", "height": "300px"})


def check_order(root):
    ids = [node.attrs["data-id"] for node in find(root, lambda n: "data-id" in n.attrs)]
    if ids != ORDER:
        raise AssertionError("order %s" % ids)


def check_solid(root):
    expect_style(by_id(root, "t2"), {"left": "40px", "top": "40px", "width": "40px", "height": "40px", "background-color": "rgb(255, 0, 0)"})


def check_image(root):
    node = by_id(root, "t3")
    expect_style(node, {"opacity": "0.5"})
    if not node.style().get("background-image", "").startswith('url("data:image/png'):
        raise AssertionError("background-image %r" % node.style().get("background-image"))


def check_placeholder(root):
    node = by_id(root, "t4")
    if "placeholder" not in node.classes():
        raise AssertionError("classes %s" % node.classes())
    label = one(node, lambda n: n.tag == "span" and "label" in n.classes(), "span.label")
    if label.text() != "missing":
        raise AssertionError("label %r" % label.text())


def check_runs(root):
    spans = find(by_id(root, "s5"), lambda n: n.tag == "span")
    runs = [(span.text(), span.style().get("color")) for span in spans]
    want = [("Hello ", "rgb(255, 255, 255)"), ("red", "rgb(255, 0, 0)"), (" world", "rgb(255, 255, 255)")]
    if runs != want:
        raise AssertionError("runs %s" % runs)


def check_inline(root):
    node = by_id(root, "s6")
    one(node, lambda n: n.tag == "img" and "inline" in n.classes(), "img.inline")
    one(node, lambda n: n.tag == "span" and {"inline", "placeholder"} <= set(n.classes()), "span.inline.placeholder")


def check_clip(root):
    node = by_id(root, "t7")
    if "clip" not in node.parent.classes():
        raise AssertionError("parent classes %s" % node.parent.classes())
    expect_style(node.parent, {"left": "220px", "top": "120px", "width": "40px", "height": "40px"})
    expect_style(node, {"left": "-20px", "top": "-20px"})


def check_widgets(root):
    expect_style(one(by_id(root, "f8"), by_class("fill"), ".fill"), {"width": "50%"})
    box = by_id(root, "f9")
    text = one(box, by_class("text"), ".text")
    if text.text() != "abc":
        raise AssertionError(".text %r" % text.text())
    one(box, by_class("caret"), ".caret")


def check_backdrop(root):
    expect_style(by_id(root, "b1.center"), {"background-color": "rgba(26, 26, 26, 0.9)"})
    expect_style(by_id(root, "b1.edge"), {"border": "1px solid rgb(255, 255, 255)"})


def check_auto_width(root):
    auto = one(by_id(root, "s10"), by_class("lines"), "s10 .lines")
    if "auto" not in auto.classes():
        raise AssertionError("s10 .lines classes %s" % auto.classes())
    expect_style(auto, {"white-space": "pre"})
    fixed = one(by_id(root, "s5"), by_class("lines"), "s5 .lines")
    if "auto" in fixed.classes():
        raise AssertionError("s5 .lines classes %s" % fixed.classes())


def check_errors(root):
    errors = one(root, lambda n: n.attrs.get("id") == "errors", "#errors")
    if "boom" not in errors.text():
        raise AssertionError("#errors %r" % errors.text())


CHECKS = [
    ("ready flag, stage 400x300", check_ready),
    ("item order", check_order),
    ("solid texture t2", check_solid),
    ("image texture t3", check_image),
    ("placeholder t4", check_placeholder),
    ("colour runs s5", check_runs),
    ("inline escapes s6", check_inline),
    ("clip t7", check_clip),
    ("widgets f8 f9", check_widgets),
    ("backdrop pieces of f1", check_backdrop),
    ("errors banner", check_errors),
    ("auto-width text s10", check_auto_width),
] + FEATURE_CHECKS


def main(argv):
    if len(argv) != 2:
        print("usage: check_dom.py <dom.html>")
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
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
