"""Tests for the window DB2 exports (Task 12.2): WINDOW_TABLES, the per-key index files, chunked tables and their indexes,
skipped tables and the column whitelist."""

from tools.client import db2_export, dbd
from tools.client.fakes import FakeSource, lua_value, make_wdc5
from tools.client.selftest_r5 import home

BUILD = "BUILD 12.0.0.0-12.9.9.99999\n"
TALENT_TAB = f"COLUMNS\nint ID\nlocstring Name_lang\nint ClassMask\nint Junk\n\nLAYOUT 0000C0DE\n{BUILD}$id$ID<32>\nName_lang\nClassMask<32>\nJunk<32>\n"
TALENT = f"COLUMNS\nint ID\nint TabID\nint TierID\n\nLAYOUT 0000C0DF\n{BUILD}$id$ID<32>\nTabID<32>\nTierID<32>\n"
UI_MAP = f"COLUMNS\nint ID\nint Type\n\nLAYOUT 0000C0E0\n{BUILD}$id$ID<32>\nType<32>\n"


def talent_tabs(rows):
    return make_wdc5(dbd.parse(TALENT_TAB)[0].fields, rows, layout_hash=0xC0DE)


def talents(rows):
    return make_wdc5(dbd.parse(TALENT)[0].fields, rows, layout_hash=0xC0DF)


def with_tables(tables):
    """Swaps WINDOW_TABLES for `tables` and returns the real one, which the caller restores."""
    real, db2_export.WINDOW_TABLES = db2_export.WINDOW_TABLES, tables
    return real


def test_window_tables_export_when_present(tmp):
    ctx = home(tmp, TalentTab=TALENT_TAB)
    row = {"ID": 41, "Name_lang": "Arms", "ClassMask": 1, "Junk": 5}
    src = FakeSource({"dbfilesclient/talenttab.db2": talent_tabs([row])})
    assert db2_export.write(src, tmp / "out", ctx) == 1
    assert lua_value(tmp / "out/db2/talenttab.lua") == {41: {"ID": 41, "Name_lang": "Arms", "ClassMask": 1}}


def test_absent_window_table_is_noted_not_fatal(tmp):
    ctx = home(tmp, TalentTab=TALENT_TAB)  # no uimap.db2 in the source
    src = FakeSource({"dbfilesclient/talenttab.db2": talent_tabs([{"ID": 1, "Name_lang": "Fury", "ClassMask": 1, "Junk": 0}])})
    assert db2_export.write(src, tmp / "out", ctx) == 1
    assert "db2: UiMap has no listfile entry in this client" in ctx.notes, ctx.notes
    assert (tmp / "out/db2/talenttab.lua").is_file() and not (tmp / "out/db2/uimap.lua").exists()


def test_index_maps_each_value_to_ascending_row_ids(tmp):
    ctx = home(tmp, Talent=TALENT)
    rows = [{"ID": 7, "TabID": 3, "TierID": 0}, {"ID": 5, "TabID": 3, "TierID": 1}, {"ID": 6, "TabID": 4, "TierID": 0}]
    src = FakeSource({"dbfilesclient/talent.db2": talents(rows)})
    assert db2_export.write(src, tmp / "out", ctx) == 2  # the table and its TabID index
    assert lua_value(tmp / "out/db2/index/talent.tabid.lua") == {3: [5, 7], 4: [6]}
    assert sorted(lua_value(tmp / "out/db2/talent.lua")) == [5, 6, 7]


def test_chunked_table_and_index_chunk_by_id_and_by_value(tmp):
    ctx = home(tmp, Talent=TALENT)
    (tmp / "out/db2/index").mkdir(parents=True)
    (tmp / "out/db2/talent.lua").write_text("return {}")  # an older single-file export of the table and of its index
    (tmp / "out/db2/index/talent.tabid.lua").write_text("return {}")
    rows = [{"ID": 5, "TabID": 3, "TierID": 0}, {"ID": 10005, "TabID": 10003, "TierID": 1}]
    src = FakeSource({"dbfilesclient/talent.db2": talents(rows)})
    real = with_tables({"Talent": {"columns": ("ID", "TabID"), "chunked": True, "index": ("TabID",)}})
    try:
        assert db2_export.write(src, tmp / "out", ctx) == 4
    finally:
        db2_export.WINDOW_TABLES = real
    assert lua_value(tmp / "out/db2/talent/0.lua") == {5: {"ID": 5, "TabID": 3}}
    assert lua_value(tmp / "out/db2/talent/1.lua") == {10005: {"ID": 10005, "TabID": 10003}}
    assert lua_value(tmp / "out/db2/index/talent.tabid/0.lua") == {3: [5]}
    assert lua_value(tmp / "out/db2/index/talent.tabid/1.lua") == {10003: [10005]}
    assert not (tmp / "out/db2/talent.lua").exists() and not (tmp / "out/db2/index/talent.tabid.lua").exists()


def test_columns_are_whitelisted(tmp):
    ctx = home(tmp, TalentTab=TALENT_TAB)
    src = FakeSource({"dbfilesclient/talenttab.db2": talent_tabs([{"ID": 41, "Name_lang": "Fury", "ClassMask": 1, "Junk": 9}])})
    db2_export.write(src, tmp / "out", ctx)
    assert "Junk" not in lua_value(tmp / "out/db2/talenttab.lua")[41]  # a row field outside `columns` never reaches the file
    assert "db2: TalentTab: column OrderIndex is not in the DBD, skipped" in ctx.notes, ctx.notes


def test_window_tables_name_no_layout_absent_columns(tmp):
    tables = db2_export.WINDOW_TABLES
    for name, spec in tables.items():
        for column in ("_Index", "RaceMask", "PetTalentMask", "TextureName", "BkgAtlasID"):
            assert column not in spec["columns"], (name, column)
    assert "Index" in tables["TraitNodeXTraitNodeEntry"]["columns"]
    assert "Stackable" in db2_export.R5_COLUMNS["ItemSparse"]
    for name, spec in tables.items():  # an index column is a column the table keeps
        assert set(spec.get("index", ())) <= set(spec["columns"]), name


TESTS = [
    test_window_tables_export_when_present,
    test_absent_window_table_is_noted_not_fatal,
    test_index_maps_each_value_to_ascending_row_ids,
    test_chunked_table_and_index_chunk_by_id_and_by_value,
    test_columns_are_whitelisted,
    test_window_tables_name_no_layout_absent_columns,
]
