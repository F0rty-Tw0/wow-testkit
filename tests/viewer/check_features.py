"""Per-feature DOM checks for the items t11..s31 of the basic fixture (see check_dom.py).

The font of s25 is a 848-byte TrueType font whose every glyph is a box, built with fontTools and inlined as a data: url,
so a loaded face shows as boxes in basic.png and as a "wtk-font-N" family in the DOM.
"""

from dom_tree import by_class, by_id, expect_style, find, one

WHITE = "rgb(255, 255, 255)"


def expect_equal(got, want, what):
    if got != want:
        raise AssertionError("%s %r, want %r" % (what, got, want))


def lacks_style_of(node, key):
    if key in node.style():
        raise AssertionError("unexpected %s: %r" % (key, node.style()[key]))


def lacks_style(root, item_id, key):
    lacks_style_of(by_id(root, item_id), key)


def runs_of(root, item_id):
    spans = find(by_id(root, item_id), lambda n: n.tag == "span")
    return [(span.text(), span.style().get("color")) for span in spans]


def check_tex_coord(root):
    expect_style(by_id(root, "t11"), {"background-size": "40px 40px", "background-position": "-20px 0px"})
    expect_style(by_id(root, "t3"), {"background-size": "100% 100%", "background-position": "0px 0px"})


def check_gradient(root):
    expect_style(by_id(root, "t12"), {"background-image": "linear-gradient(to right, rgb(255, 0, 0), rgb(0, 0, 255))"})


def check_rotation(root):
    expect_style(by_id(root, "t13"), {"transform": "rotate(-0.5rad)"})
    lacks_style(root, "t3", "transform")


def check_add_blend(root):
    expect_style(by_id(root, "t14"), {"mix-blend-mode": "plus-lighter"})
    lacks_style(root, "t3", "mix-blend-mode")


def check_desaturated(root):
    expect_style(by_id(root, "t15"), {"filter": "grayscale(1)"})
    lacks_style(root, "t3", "filter")


def check_tiling(root):
    expect_style(by_id(root, "t16"), {"background-repeat": "repeat-x"})
    expect_style(by_id(root, "t17"), {"background-repeat": "repeat-y"})
    expect_style(by_id(root, "t18"), {"background-repeat": "repeat"})
    expect_style(by_id(root, "t3"), {"background-repeat": "no-repeat"})


def check_slider(root):
    thumb = one(by_id(root, "f19"), by_class("thumb"), "f19 .thumb")
    if "horizontal" not in thumb.classes():
        raise AssertionError("thumb classes %s" % thumb.classes())
    expect_style(thumb, {"left": "calc(25% - 2px)", "transform": "none"})


def check_check_button(root):
    one(by_id(root, "f20"), by_class("check"), "f20 .check")
    unchecked = find(by_id(root, "f21"), by_class("check"))
    if unchecked:
        raise AssertionError("unchecked f21 has %d .check" % len(unchecked))


def check_message_frame(root):
    lines = find(by_id(root, "f22"), by_class("line"))
    expect_equal([line.text() for line in lines], ["first", "second red", "third"], "f22 .line texts")
    first = one(lines[0], lambda n: n.tag == "span", "first line span")
    expect_equal(first.style().get("color"), "rgb(255, 255, 0)", "first line colour")


def check_shadow(root):
    lines = one(by_id(root, "s23"), by_class("lines"), "s23 .lines")
    expect_style(lines, {"text-shadow": "rgb(0, 0, 255) 2px 2px 0px"})
    lacks_style_of(one(by_id(root, "s5"), by_class("lines"), "s5 .lines"), "text-shadow")


def check_max_lines(root):
    lines = one(by_id(root, "s24"), by_class("lines"), "s24 .lines")
    if "clamped" not in lines.classes():
        raise AssertionError("s24 .lines classes %s" % lines.classes())
    expect_style(lines, {"-webkit-line-clamp": "1"})
    plain = one(by_id(root, "s5"), by_class("lines"), "s5 .lines")
    if "clamped" in plain.classes():
        raise AssertionError("s5 .lines classes %s" % plain.classes())


def check_font_face(root):
    family = by_id(root, "s25").style().get("font-family", "")
    if not family.startswith("wtk-font-0, "):
        raise AssertionError("s25 font-family %r" % family)
    if "wtk-font" in by_id(root, "s5").style().get("font-family", ""):
        raise AssertionError("s5 font-family names a loaded face")


def check_escape_pipe(root):
    expect_equal(runs_of(root, "s26"), [("a|b", WHITE)], "s26 runs")


def check_escape_newline(root):
    expect_equal(runs_of(root, "s31"), [("x\ny", WHITE)], "s31 runs")


def check_escape_nested(root):
    # The colour of C after the first |r is not pinned: the viewer pops one colour, the client may reset to default.
    runs = runs_of(root, "s27")
    expect_equal(runs[0], ("A", "rgb(255, 0, 0)"), "s27 first run")
    expect_equal(runs[1], ("B", "rgb(0, 255, 0)"), "s27 second run")
    expect_equal(runs[-1][1], WHITE, "s27 last run colour")
    if not runs[-1][0].endswith("D"):
        raise AssertionError("s27 last run %r does not end in D" % (runs[-1],))


def check_escape_file_id(root):
    node = by_id(root, "s29")
    image = one(node, lambda n: n.tag == "img" and "inline" in n.classes(), "s29 img.inline")
    if not image.attrs.get("src", "").startswith("data:image/png"):
        raise AssertionError("img src %r" % image.attrs.get("src"))
    expect_style(image, {"width": "10px", "height": "10px"})
    expect_equal(runs_of(root, "s29"), [("X", WHITE)], "s29 runs")


def check_escape_hyperlink(root):
    expect_equal(runs_of(root, "s28"), [("see [Sword]", WHITE)], "s28 runs")


def check_escape_unterminated(root):
    expect_equal(runs_of(root, "s30"), [("ok ", WHITE), ("green", "rgb(0, 255, 0)")], "s30 runs")


def check_null_numbers(root):
    # A null channel reads as 1 (what the render snapshot writes for a NaN or nil colour) and a null alpha as opaque.
    node = by_id(root, "t32")
    expect_style(node, {"background-color": "rgb(255, 0, 0)"})
    lacks_style_of(node, "opacity")


CHECKS = [
    ("texCoord crop t11", check_tex_coord),
    ("gradient t12", check_gradient),
    ("rotation t13", check_rotation),
    ("ADD blend t14", check_add_blend),
    ("desaturated t15", check_desaturated),
    ("tile flags t16 t17 t18", check_tiling),
    ("slider thumb f19", check_slider),
    ("check button f20 f21", check_check_button),
    ("message frame lines f22", check_message_frame),
    ("text shadow s23", check_shadow),
    ("maxLines clamp s24", check_max_lines),
    ("font face s25", check_font_face),
    ("escape || s26", check_escape_pipe),
    ("escape |n s31", check_escape_newline),
    ("escape nested |c s27", check_escape_nested),
    ("escape |T fileID s29", check_escape_file_id),
    ("escape |H hyperlink s28", check_escape_hyperlink),
    ("escape unterminated |c s30", check_escape_unterminated),
    ("null colour channel and alpha t32", check_null_numbers),
]
