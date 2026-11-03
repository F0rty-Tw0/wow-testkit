#!/usr/bin/env python3
"""Checks the DOM and screenshot that tests/viewer/scene_png.sh makes of the 3D scene fixture.

    python tests/viewer/check_scene.py <dom.html> [scene.png]

Reads the <body> attributes tests/viewer/scene_fixture.js sets: data-done, data-gl ("webgl" or "none"), data-drawn
(meshes in the scene) and data-models (actors wearing a real model, not the capsule). Prints "PASS scene: <what>" or
"FAIL scene: <what>" per check; exit 1 on any FAIL. Without WebGL the page can only prove the math-only fallback.
"""

import struct
import sys
from html.parser import HTMLParser

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MIN_MESHES = 20
MIN_WIDTH = 1000
MIN_BYTES = 40000
MODEL_ACTORS = 4


class BodyParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.attrs = None

    def handle_starttag(self, tag, attrs):
        if tag == "body" and self.attrs is None:
            self.attrs = dict(attrs)


def body_attrs(path):
    with open(path, encoding="utf-8") as handle:
        parser = BodyParser()
        parser.feed(handle.read())

    return parser.attrs or {}


def count(attrs, name):
    value = attrs.get(name, "")

    return int(value) if value.isdigit() else -1


def png_problem(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != PNG_SIGNATURE:
        return "not a PNG"
    width = struct.unpack(">I", data[16:20])[0]
    if width < MIN_WIDTH:
        return "width %d < %d" % (width, MIN_WIDTH)
    if len(data) <= MIN_BYTES:
        return "%d bytes <= %d" % (len(data), MIN_BYTES)

    return ""


def verdicts(attrs, png):
    if attrs.get("data-done") != "1":
        return [("data-done missing", False)]
    gl = attrs.get("data-gl")
    if gl == "none":
        return [("no WebGL here, math-only fallback (spec 11 R2)", True)]
    if gl != "webgl":
        return [("data-gl is %r, want webgl or none" % gl, False)]
    drawn = count(attrs, "data-drawn")
    models = count(attrs, "data-models")
    out = [
        ("data-gl webgl", True),
        ("data-drawn %d > %d meshes" % (drawn, MIN_MESHES), drawn > MIN_MESHES),
        (
            "data-models %d == %d (player + 3 skeletons wear models, not capsules)" % (models, MODEL_ACTORS),
            models == MODEL_ACTORS,
        ),
    ]
    if png:
        problem = png_problem(png)
        proof = problem or "has signature, width >= %d, size > %d" % (MIN_WIDTH, MIN_BYTES)
        out.append(("png %s" % proof, not problem))

    return out


def main(argv):
    dom = argv[1]
    png = argv[2] if len(argv) > 2 else None
    failed = 0
    for label, ok in verdicts(body_attrs(dom), png):
        print(("PASS scene: " if ok else "FAIL scene: ") + label)
        failed += not ok

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
