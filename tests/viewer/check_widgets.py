#!/usr/bin/env python3
"""DOM assertions for the viewer widget check (tests/viewer/widgets_check.sh) on widgets_fixture.json.

    python tests/viewer/check_widgets.py <dom.html>

Prints PASS/FAIL per check and a count; exit 1 on any failure.
"""

import sys

from dom_tree import TreeParser, by_class, by_id, expect_style, find, one


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
    # Value 5 of 0..10: the leading edge of the 10px thumb is half the free 190px of the track in.
    thumb = one(by_id(root, "f3"), by_class("thumb"), ".thumb")
    expect_style(thumb, {"left": "calc(50% - 5px)", "width": "10px", "height": "20px", "background-color": "rgb(255, 0, 0)"})
    if "translateY(-50%)" not in thumb.style().get("transform", ""):
        raise AssertionError("transform %r" % thumb.style().get("transform"))


def check_thumb_stays_inside_the_track_at_both_ends(root):
    # Value 0 of 0..10: the thumb starts at the track start, not centred on it.
    start = one(by_id(root, "f10"), by_class("thumb"), "f10 .thumb")
    expect_style(start, {"left": "calc(0% - 0px)"})
    # Value 10 of 0..10 on a vertical slider (minimum at the top): the 10px thumb ends at the bottom of the track.
    end = one(by_id(root, "f14"), by_class("thumb"), "f14 .thumb")
    expect_style(end, {"top": "calc(100% - 10px)", "width": "20px", "height": "10px"})


def z_index(root, item_id):
    return int(by_id(root, item_id).style()["z-index"])


def check_textured_bar_fill_is_the_texture_times_the_bar_colour(root):
    fill = one(by_id(root, "f7"), by_class("fill"), ".fill")
    colour = fill.style().get("background-color", "").replace(" ", "")
    if colour not in ("rgb(0,255,0)", "rgba(0,255,0,1)"):
        raise AssertionError("fill colour %r, want green" % colour)
    expect_style(fill, {"width": "50%"})


def check_bar_fill_draws_above_the_background_and_below_the_text(root):
    background, bar, text = z_index(root, "t8"), z_index(root, "f7"), z_index(root, "s9")
    if not background < bar < text:
        raise AssertionError("z-index background %d, bar %d, text %d, want background < bar < text" % (background, bar, text))


def check_thumb_draws_above_the_background(root):
    background, slider = z_index(root, "t11"), z_index(root, "f10")
    if not background < slider:
        raise AssertionError("z-index background %d, slider %d, want background < slider" % (background, slider))


def check_checked_box_with_art_has_no_stand_in_mark(root):
    marks = find(by_id(root, "f12"), by_class("check"))
    if marks:
        raise AssertionError("checked f12 with a checked texture has %d .check" % len(marks))


def check_file_textured_bar_fill_draws_its_image(root):
    fill = one(by_id(root, "f13"), by_class("fill"), ".fill")
    expect_style(fill, {"width": "40%"})
    image = fill.style().get("background-image", "")
    if "data:image/png" not in image:
        raise AssertionError("fill background-image %r, want the file texture" % image)


CHECKS = [
    ("edit selection", check_selection),
    ("reversed status bar fill", check_reversed_fill),
    ("centre status bar fill", check_center_fill),
    ("reverse fill style status bar", check_reverse_fill_style),
    ("slider thumb at the value fraction", check_thumb),
    ("textured bar fill is the texture times the bar colour", check_textured_bar_fill_is_the_texture_times_the_bar_colour),
    ("bar fill draws above its background and below its text", check_bar_fill_draws_above_the_background_and_below_the_text),
    ("slider thumb stays inside the track at both ends", check_thumb_stays_inside_the_track_at_both_ends),
    ("slider thumb draws above its background", check_thumb_draws_above_the_background),
    ("a checked box with art has no stand-in mark", check_checked_box_with_art_has_no_stand_in_mark),
    ("a file textured bar fill draws its image", check_file_textured_bar_fill_draws_its_image),
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
