"""Tests for the font writer: glyph tables from cmap, hmtx, legacy kern and GPOS, and the preview-side lookup."""

import sys
from pathlib import Path

from tools.client import fonts
from tools.client.extract import Ctx
from tools.client.fakes import FakeSource, lua_value, make_ttf

TOOLS = str(Path(__file__).resolve().parent.parent)
GLYPHS = {"A": 700, "V": 700, "space": 300}


def ctx():
    return Ctx("retail", "wow", "1", "1.0.0.1", ["enUS"])


def test_advance_by_codepoint(tmp):
    t = fonts.glyph_table(make_ttf(GLYPHS))
    assert t["upm"] == 1000 and t["advance"][65] == 700 and t["advance"][32] == 300 and t["notdef"] == 500


def test_legacy_kern_pair(tmp):
    t = fonts.glyph_table(make_ttf({"A": 700, "V": 700}, kern={("A", "V"): -80}))
    assert t["kern"] == {65 * fonts.KERN_SHIFT + 86: -80}


def test_gpos_kern_pair(tmp):
    t = fonts.glyph_table(make_ttf({"A": 700, "V": 700}, fea="feature kern { pos A V -50; } kern;"))
    assert t["kern"][65 * fonts.KERN_SHIFT + 86] == -50


def test_gpos_class_pairs_expand_over_both_classes(tmp):
    fea = "@L = [A V]; @R = [A V space]; feature kern { pos @L @R -30; pos A V -50; } kern;"
    kern = fonts.glyph_table(make_ttf(GLYPHS, fea=fea))["kern"]
    assert kern[65 * fonts.KERN_SHIFT + 86] == -50 and kern[86 * fonts.KERN_SHIFT + 32] == -30
    assert len(kern) == 6


def test_no_kerning_gives_empty_kern(tmp):
    assert fonts.glyph_table(make_ttf(GLYPHS))["kern"] == {}


def test_write_copies_ttf_and_glyph_table_loads_in_lua51(tmp):
    ttf = make_ttf(GLYPHS, kern={("A", "V"): -80})
    src = FakeSource({"fonts/frizqt__.ttf": ttf, "interface/buttons/a.blp": b"x"})
    assert fonts.write(src, tmp, ctx()) == 1
    assert (tmp / "fonts/frizqt__.ttf").read_bytes() == ttf
    table = lua_value(tmp / "fonts/glyphs/frizqt__.ttf.lua")
    assert table["upm"] == 1000 and table["notdef"] == 500 and table["advance"][65] == 700
    assert table["kern"][65 * 0x200000 + 86] == -80


def test_corrupt_font_is_skipped_and_noted(tmp):
    c = ctx()
    assert fonts.write(FakeSource({"fonts/bad.ttf": b"nope"}), tmp, c) == 0
    assert len(c.notes) == 1 and "fonts/bad.ttf" in c.notes[0]
    assert not (tmp / "fonts").exists()


def test_drive_relative_font_name_is_skipped_and_noted(tmp):
    c = ctx()
    out = tmp / "out"
    assert fonts.write(FakeSource({"fonts/c:evil.ttf": make_ttf(GLYPHS)}), out, c) == 0  # on Windows: c:evil.ttf
    assert c.notes == ["fonts: skipped unsafe path 'fonts/c:evil.ttf'"], c.notes
    assert not out.exists() and not list(tmp.rglob("*evil*")) and not Path("evil.ttf").exists()


def test_lookup_extract_serves_fonts(tmp):
    sys.path.insert(0, TOOLS)
    import preview_assets

    (tmp / "fonts").mkdir()
    (tmp / "fonts/frizqt__.ttf").write_bytes(make_ttf(GLYPHS))
    ask = lambda path: preview_assets.lookup_extract(str(tmp), "font:" + path.lower(), {"kind": "font", "path": path})
    assert ask("Fonts\FRIZQT__.TTF") == tmp / "fonts/frizqt__.ttf"
    assert ask("Fonts\missing.ttf") is None and ask("Fonts\..\manifest.json") is None


TESTS = [
    test_advance_by_codepoint,
    test_legacy_kern_pair,
    test_gpos_kern_pair,
    test_gpos_class_pairs_expand_over_both_classes,
    test_no_kerning_gives_empty_kern,
    test_write_copies_ttf_and_glyph_table_loads_in_lua51,
    test_corrupt_font_is_skipped_and_noted,
    test_drive_relative_font_name_is_skipped_and_noted,
    test_lookup_extract_serves_fonts,
]
