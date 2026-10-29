#!/usr/bin/env python3
"""DOM assertions for the live viewer (tests/viewer/live_check.sh) on the SessionDemo session.

    python tests/viewer/check_live.py <live.html> <live-select.html>

live.html is the page at ?live=1&stream=0, live-select.html the same page with &select=SessionDemoFrame. Prints PASS/FAIL
per numbered check; exit 1 on any failure. Later tasks append checks.
"""

import sys

from dom_tree import TreeParser, by_class, find, one


def check_ready(root):
    html = one(root, lambda n: n.tag == "html", "html")
    if html.attrs.get("data-ready") != "1":
        raise AssertionError("data-ready=%r" % html.attrs.get("data-ready"))
    one(root, lambda n: n.attrs.get("data-name") == "SessionDemoFrame", "[data-name=SessionDemoFrame]")


def check_hover(root):
    hover = one(root, lambda n: n.attrs.get("id") == "hover", "#hover")
    if "hidden" not in hover.attrs:
        raise AssertionError("#hover is shown")


def inspector(root):
    return one(root, lambda n: n.attrs.get("id") == "inspector", "#inspector")


def tree_row(panel, name):
    """The li[data-id] of the inspector tree whose own label (not a descendant's) names `name`."""

    def labelled(li):
        own = li.children[0] if li.children else li
        return any("node-name" in n.classes() and n.text() == name for n in own.walk())

    rows = find(panel, lambda n: n.tag == "li" and "data-id" in n.attrs and labelled(n))
    if len(rows) != 1:
        raise AssertionError("expected one tree row for %s, found %d" % (name, len(rows)))
    return rows[0]


def check_tree(root):
    panel = inspector(root)
    drawn = one(root, lambda n: n.attrs.get("data-name") == "SessionDemoFrame", "[data-name=SessionDemoFrame]")
    row = tree_row(panel, "SessionDemoFrame")
    if row.attrs["data-id"] != drawn.attrs.get("data-id"):
        raise AssertionError("tree row id %r, stage id %r" % (row.attrs["data-id"], drawn.attrs.get("data-id")))
    hidden = tree_row(panel, "SessionDemoHidden")
    if "dim" not in hidden.classes():
        raise AssertionError("hidden node classes %r" % hidden.classes())


def check_selected(root):
    props = one(inspector(root), lambda n: n.tag == "dl", "inspector dl")
    text = props.text()
    for wanted in ("SessionDemoFrame", "MEDIUM", "CENTER"):
        if wanted not in text:
            raise AssertionError("%s not in properties %r" % (wanted, text[:300]))
    selection = one(root, lambda n: n.attrs.get("id") == "selection", "#selection")
    if "hidden" in selection.attrs:
        raise AssertionError("#selection is hidden")
    one(inspector(root), by_class("selected"), "selected tree row")


def element(root, name):
    return one(root, lambda n: n.attrs.get("id") == name, "#" + name)


def check_panels(root):
    for name in ("console", "events", "state"):
        element(root, name)
    one(element(root, "cmdline"), lambda n: n.tag == "input", "#cmdline input")


def check_event_names(root):
    datalist = one(element(root, "events"), lambda n: n.tag == "datalist", "#events datalist")
    names = {n.attrs.get("value") for n in find(datalist, lambda n: n.tag == "option")}
    if "PLAYER_REGEN_DISABLED" not in names:
        raise AssertionError("PLAYER_REGEN_DISABLED not among %d event names" % len(names))


def check_input_frames(root):
    for name in ("SessionDemoKeys", "SessionDemoDrag", "SessionDemoWheel"):
        one(root, lambda n, name=name: n.attrs.get("data-name") == name, "[data-name=%s]" % name)


def option_values(root, name):
    select = one(element(root, "toolbar"), lambda n: n.tag == "select" and n.attrs.get("id") == name, "#toolbar #" + name)
    return [n.attrs.get("value") for n in find(select, lambda n: n.tag == "option")]


def check_flavor_picker(root):
    values = option_values(root, "flavor")
    if values != ["auto", "retail", "mists", "vanilla", "tbc", "forever"]:
        raise AssertionError("#flavor options %r" % values)


def check_size_picker(root):
    values = option_values(root, "size")
    if values != ["1080p", "1440p", "4k", "custom"]:
        raise AssertionError("#size options %r" % values)
    text = element(root, "session-status").text()
    if "SessionDemo" not in text:
        raise AssertionError("status line %r" % text)


def check_dev(root):
    panel = element(root, "dev")
    one(panel, lambda n: n.tag == "tr" and n.attrs.get("data-addon") == "SessionDemo", '#dev tr[data-addon="SessionDemo"]')
    if "Memory (estimate)" not in panel.text():
        raise AssertionError("no Memory (estimate) header in %r" % panel.text()[:200])


def check_combat(root):
    bar = element(root, "combat")
    select = one(bar, lambda n: n.tag == "select" and n.attrs.get("id") == "combat-preset", "#combat #combat-preset")
    values = [n.attrs.get("value") for n in find(select, lambda n: n.tag == "option")]
    if values != ["solo", "dungeon", "raid:10", "raid:20", "raid:25", "raid:40"]:
        raise AssertionError("#combat-preset options %r" % values)
    race = one(bar, lambda n: n.tag == "select" and n.attrs.get("id") == "combat-race", "#combat #combat-race")
    names = [n.text() for n in find(race, lambda n: n.tag == "option")]
    if "Human" not in names:
        raise AssertionError("#combat-race options %r" % names)
    one(element(root, "combatlog"), lambda n: n.tag == "ol", "#combatlog ol")


def check_blizzard(root):
    panel = element(root, "blizzard")
    toggle = one(panel, lambda n: n.attrs.get("id") == "blizzard-toggle", "#blizzard #blizzard-toggle")
    if toggle.tag != "input" or toggle.attrs.get("type") != "checkbox" or "disabled" not in toggle.attrs:
        raise AssertionError("#blizzard-toggle %s %r is not a disabled checkbox" % (toggle.tag, toggle.attrs))
    one(panel, lambda n: n.tag == "select" and n.attrs.get("id") == "blizzard-layout", "#blizzard select#blizzard-layout")
    one(panel, lambda n: n.tag == "input" and n.attrs.get("id") == "blizzard-actions", "#blizzard input#blizzard-actions")
    if "no client extract" not in panel.text():
        raise AssertionError("no 'no client extract' hint in %r" % panel.text()[:200])


def check_window_picker(root):
    panel = element(root, "blizzard")
    select = one(panel, lambda n: n.tag == "select" and n.attrs.get("id") == "blizzard-window", "#blizzard select#blizzard-window")
    labels = [n.text() for n in find(select, lambda n: n.tag == "option")]
    if labels != ["no Blizzard windows"] or "disabled" not in select.attrs:
        raise AssertionError("#blizzard-window %r disabled=%s" % (labels, "disabled" in select.attrs))


# (name, check, which DOM: 0 = live.html, 1 = live-select.html)
CHECKS = [
    ("ready flag, live snapshot drawn", check_ready, 0),
    ("hover outline hidden", check_hover, 0),
    ("inspector tree lists the frame and dims the hidden one", check_tree, 0),
    ("select= shows the frame's properties and outline", check_selected, 1),
    ("console, events, state and command line panels", check_panels, 0),
    ("events datalist names PLAYER_REGEN_DISABLED", check_event_names, 0),
    ("the keys, drag and wheel frames are drawn", check_input_frames, 0),
    ("toolbar #flavor lists auto then the five flavors", check_flavor_picker, 0),
    ("toolbar #size lists the presets and custom; the status line names the addon", check_size_picker, 0),
    ("#dev lists SessionDemo under a Memory (estimate) header", check_dev, 0),
    ("#combat has the preset options and the race select; #combatlog exists", check_combat, 0),
    ("#blizzard has the toggle (disabled, no extract), the layout select and the actions line", check_blizzard, 0),
    ("#blizzard-window offers no Blizzard windows (disabled) without the layer", check_window_picker, 0),
]


def parse(path):
    parser = TreeParser()
    with open(path, encoding="utf-8", errors="replace") as handle:
        parser.feed(handle.read())
    return parser.root


def main(argv):
    if len(argv) != 3:
        print("usage: check_live.py <live.html> <live-select.html>")
        return 2
    roots = [parse(path) for path in argv[1:]]
    failed = 0
    for number, (name, check, which) in enumerate(CHECKS, 1):
        try:
            check(roots[which])
            print("PASS %s (%d)" % (name, number))
        except AssertionError as err:
            failed += 1
            print("FAIL %s (%d): %s" % (name, number, err))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
