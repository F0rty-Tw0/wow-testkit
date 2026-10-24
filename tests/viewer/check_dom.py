#!/usr/bin/env python3
"""DOM assertions for the viewer check (tests/viewer/check.sh) on the basic fixture.

    python tests/viewer/check_dom.py <dom.html>

Prints PASS/FAIL per check; exit 1 on any failure.
"""

import sys
from html.parser import HTMLParser

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
ORDER = ["f1", "t2", "t3", "t4", "s5", "s6", "t7", "f8", "f9"]


class Node:
    def __init__(self, tag, attrs, parent):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        self.children, self.texts = [], []

    def classes(self):
        return (self.attrs.get("class") or "").split()

    def style(self):
        pairs = [part.split(":", 1) for part in (self.attrs.get("style") or "").split(";") if ":" in part]
        return {key.strip(): value.strip() for key, value in pairs}

    def text(self):
        return "".join(self.texts) + "".join(child.text() for child in self.children)

    def walk(self):
        for child in self.children:
            yield child
            yield from child.walk()


class TreeParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#document", [], None)
        self.current = self.root

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.current)
        self.current.children.append(node)
        if tag not in VOID:
            self.current = node

    def handle_endtag(self, tag):
        node = self.current
        while node is not self.root and node.tag != tag:
            node = node.parent
        if node is not self.root:
            self.current = node.parent

    def handle_data(self, data):
        self.current.texts.append(data)


def find(root, pred):
    return [node for node in root.walk() if pred(node)]


def one(root, pred, what):
    found = find(root, pred)
    if len(found) != 1:
        raise AssertionError("expected one %s, found %d" % (what, len(found)))
    return found[0]


def by_id(root, item_id):
    return one(root, lambda n: n.attrs.get("data-id") == item_id, "item " + item_id)


def by_class(name):
    return lambda n: name in n.classes()


def expect_style(node, expected):
    style = node.style()
    wrong = {key: style.get(key) for key, value in expected.items() if style.get(key) != value}
    if wrong:
        raise AssertionError("style %s, want %s" % (wrong, expected))


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
    backdrop = one(by_id(root, "f1"), by_class("backdrop"), ".backdrop")
    expect_style(backdrop, {"background-color": "rgba(26, 26, 26, 0.9)"})


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
    ("backdrop f1", check_backdrop),
    ("errors banner", check_errors),
]


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
