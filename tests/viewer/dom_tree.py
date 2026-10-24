"""Tiny HTML tree and assertion helpers shared by the viewer DOM checks (check_dom.py, check_features.py)."""

from html.parser import HTMLParser

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


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
