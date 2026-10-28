#!/usr/bin/env python3
"""The compatibility catalog as one self-contained HTML page (tk catalog --html runs it).

    python tools/catalog_page.py <catalog.json> <out.html>
    python tools/catalog_page.py --selftest

catalog.json is catalog.lua's document: { ver, kind = "catalog", date, blizzardUi, listed, missing, smoke }, smoke being
the tk smoke --json document. The page is an addon x flavor matrix whose cells carry a pass, fail or skipped class, the
first error of a failing cell, the reason of a skipped one and the most called unscripted names, then the listed addons
the folder lacks. Inline CSS only: no script, no src=, no url(, no external link; every string goes through
html.escape. Exit 0; 2 on a usage error or a file that is not a catalog document.
"""

import html
import json
import sys
import tempfile
import traceback
from pathlib import Path

USAGE = "usage: catalog_page.py <catalog.json> <out.html> | catalog_page.py --selftest"
UNSCRIPTED_TOP = 3
STATUSES = ("pass", "fail", "skipped")

# The viewer's colour tokens (viewer/viewer.css): fail uses its banner pair, pass its accent, skipped its muted ink.
STYLE = """
:root { color-scheme: light dark; --page: #eef0f3; --ink: #1d2128; --panel: #ffffff; --line: #d3d7de;
  --muted: #5d6573; --accent: #cfe3ff; --banner: #fde7e5; --banner-ink: #8c1d18; }
@media (prefers-color-scheme: dark) {
  :root { --page: #15171c; --ink: #e6e8ec; --panel: #1d2027; --line: #333844; --muted: #9aa3b2;
    --accent: #23395c; --banner: #3b1d1b; --banner-ink: #ffb4ab; }
}
body { margin: 16px; background: var(--page); color: var(--ink); font: 14px/1.4 system-ui, sans-serif; }
h1 { font-size: 20px; margin: 0 0 4px; }
p.meta, .hint { color: var(--muted); margin: 0 0 12px; }
.legend { display: flex; flex-wrap: wrap; gap: 8px; margin: 0 0 12px; padding: 0; list-style: none; }
.legend li, td { border: 1px solid var(--line); }
.legend li { padding: 2px 8px; border-radius: 4px; }
table { border-collapse: collapse; width: 100%; background: var(--panel); }
th, td { padding: 6px 8px; text-align: left; vertical-align: top; overflow-wrap: anywhere; }
th { border-bottom: 2px solid var(--line); }
.pass { background: var(--accent); }
.fail { background: var(--banner); color: var(--banner-ink); }
.skipped { color: var(--muted); }
.status { font-weight: 600; text-transform: uppercase; font-size: 12px; }
.error, .unscripted { display: block; font-size: 12px; margin-top: 2px; }
@media (max-width: 600px) {
  thead { display: none; }
  table, tbody, tr, th, td { display: block; }
  tr { margin-bottom: 12px; border: 1px solid var(--line); }
  td::before { content: attr(data-flavor) ": "; font-weight: 600; }
}
"""


def esc(value):
    return html.escape(str(value), quote=True)


def top_unscripted(run):
    names = sorted(run.get("unscripted", []), key=lambda e: (-e["count"], e["name"]))[:UNSCRIPTED_TOP]
    return ", ".join("%s x%d" % (e["name"], e["count"]) for e in names)


def cell(flavor, run):
    status = run.get("status", "skipped")
    css = status if status in STATUSES else "fail"
    parts = ['<td class="%s" data-flavor="%s"><span class="status">%s</span>' % (css, esc(flavor), esc(status))]
    errors = run.get("errors") or []
    if status == "fail" and errors:
        parts.append('<span class="error">%s</span>' % esc(errors[0].get("message", "")))
    if status == "skipped" and run.get("reason"):
        parts.append('<span class="error">%s</span>' % esc(run["reason"]))
    unscripted = top_unscripted(run)
    if unscripted:
        parts.append('<span class="unscripted">unscripted: %s</span>' % esc(unscripted))
    return "".join(parts) + "</td>"


def matrix(smoke):
    flavors = smoke.get("flavors", [])
    head = "".join('<th scope="col">%s</th>' % esc(f) for f in flavors)
    rows = []
    for addon in smoke.get("addons", []):
        cells = "".join(cell(f, addon["runs"].get(f, {})) for f in flavors)
        rows.append('<tr><th scope="row">%s</th>%s</tr>' % (esc(addon["name"]), cells))
    body = "".join(rows) or '<tr><td class="skipped">no listed addon is in the folder</td></tr>'
    return '<table><thead><tr><th scope="col">Addon</th>%s</tr></thead><tbody>%s</tbody></table>' % (head, body)


def page(doc):
    smoke = doc.get("smoke", {})
    totals = smoke.get("totals", {})
    layer = "on" if doc.get("blizzardUi") else "off"
    meta = "%s · Blizzard UI %s · %d listed · %d pass, %d fail, %d skipped" % (
        doc.get("date", "?"),
        layer,
        len(doc.get("listed", [])),
        totals.get("pass", 0),
        totals.get("fail", 0),
        totals.get("skipped", 0),
    )
    legend = "".join('<li class="%s">%s</li>' % (s, s) for s in STATUSES)
    missing = doc.get("missing", [])
    lack = '<h2>Not in the folder</h2><ul class="missing">%s</ul>' % "".join("<li>%s</li>" % esc(n) for n in missing) if missing else ""
    return (
        '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        "<title>Addon catalog</title><style>%s</style></head><body>"
        '<h1>Addon catalog</h1><p class="meta">%s</p><ul class="legend">%s</ul>%s%s</body></html>\n'
    ) % (STYLE, esc(meta), legend, matrix(smoke), lack)


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if len(argv) != 2:
        print(USAGE)
        return 2
    try:
        doc = json.loads(Path(argv[0]).read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        print("catalog_page: cannot read %s: %s" % (argv[0], err))
        return 2
    if not isinstance(doc, dict) or doc.get("kind") != "catalog":
        print("catalog_page: %s is not a catalog document" % argv[0])
        return 2
    Path(argv[1]).write_text(page(doc), encoding="utf-8", newline="\n")
    return 0


# Selftest ---------------------------------------------------------------------------------------------------------


def sample(message="boom"):
    run = {"status": "fail", "errors": [{"message": message}], "printed": 0, "unscripted": [{"name": "Zed", "count": 1}, {"name": "Alpha", "count": 4}]}
    runs = {"retail": {"status": "pass", "errors": [], "printed": 0, "unscripted": []}, "vanilla": run}
    good = {"name": "Good", "runs": runs}
    skipped = {"status": "skipped", "reason": "no TOC for this flavor", "errors": [], "printed": 0, "unscripted": []}
    late = {"name": "Late", "runs": {"retail": skipped, "vanilla": skipped}}
    totals = {"addons": 2, "runs": 4, "pass": 1, "fail": 1, "skipped": 2}
    smoke = {"ver": 1, "flavors": ["retail", "vanilla"], "addons": [good, late], "totals": totals}
    return {"ver": 1, "kind": "catalog", "date": "2026-10-28", "blizzardUi": False, "listed": ["Good", "Late", "Gone"], "missing": ["Gone"], "smoke": smoke}


def render(tmp, doc):
    src, out = tmp / "c.json", tmp / "c.html"
    src.write_text(json.dumps(doc), encoding="utf-8")
    assert main([str(src), str(out)]) == 0
    return out.read_text(encoding="utf-8")


def test_cells_and_classes(tmp):
    text = render(tmp, sample())
    assert text.count("<tr><th scope=\"row\">") == 2, text
    assert '<td class="pass" data-flavor="retail">' in text and '<td class="fail" data-flavor="vanilla">' in text
    assert text.count('<td class="skipped"') == 2
    assert "unscripted: Alpha x4, Zed x1" in text and "no TOC for this flavor" in text


def test_messages_are_escaped(tmp):
    text = render(tmp, sample("<script>alert(1)</script>"))
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in text and "<script>alert" not in text


def test_page_is_self_contained(tmp):
    text = render(tmp, sample())
    for banned in ("<script", "src=", "url(", "http://", "https://", "<link", "<a "):
        assert banned not in text, banned


def test_missing_addons_are_listed(tmp):
    assert '<ul class="missing"><li>Gone</li></ul>' in render(tmp, sample())
    doc = sample()
    doc["missing"] = []
    assert "missing" not in render(tmp, doc).split("</style>")[1]


def test_bad_input_is_a_usage_error(tmp):
    (tmp / "x.json").write_text('{"ver": 1}', encoding="utf-8")
    assert main([str(tmp / "x.json"), str(tmp / "x.html")]) == 2
    assert main([str(tmp / "none.json"), str(tmp / "x.html")]) == 2
    assert main([]) == 2


TESTS = [test_cells_and_classes, test_messages_are_escaped, test_page_is_self_contained, test_missing_addons_are_listed, test_bad_input_is_a_usage_error]


def selftest():
    passed = failed = 0
    for test in TESTS:
        try:
            with tempfile.TemporaryDirectory() as tmp:
                test(Path(tmp))
            print("PASS " + test.__name__)
            passed += 1
        except Exception:
            print("FAIL " + test.__name__)
            traceback.print_exc()
            failed += 1
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
