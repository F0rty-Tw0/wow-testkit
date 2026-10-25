"""Tests for the spell and item DB2 exports (R5): sparse records, the column whitelist, id-range chunks, skipped and
locked tables."""

from tools.client import db2, db2_export, dbd
from tools.client.extract import Ctx
from tools.client.fakes import FakeSource, lua_value, make_wdc5

CTX_ARGS = dict(flavor="retail", product="wow", build="70575", version="12.1.5.70575", locales=["enUS"])
SPELL_NAME = "COLUMNS\nint ID\nlocstring Name_lang\n\nLAYOUT CAFEF00D\nBUILD 12.0.0.0-12.9.9.99999\n$id$ID<32>\nName_lang\n"
SPELL_MISC = (
    "COLUMNS\nint ID\nint SpellID\nint SpellIconFileDataID\nint SchoolMask\nint Flags\nfloat Speed\n\nLAYOUT 0000A5A5\n"
    "BUILD 12.0.0.0-12.9.9.99999\n$id$ID<32>\nSpellIconFileDataID<32>\nSchoolMask<32>\nFlags<32>[2]\nSpeed\n$noninline,relation$SpellID<32>\n"
)
ITEM = (
    "COLUMNS\nint ID\nint ClassID\nint IconFileDataID\nint Junk\n\nLAYOUT 000000B1\nBUILD 12.0.0.0-12.9.9.99999\n"
    "$id$ID<32>\nClassID<32>\nIconFileDataID<32>\nJunk<32>\n"
)
NAMES = dbd.parse(SPELL_NAME)[0].fields


def home(tmp, **dbds):
    cache = tmp / "h" / "dbd"
    cache.mkdir(parents=True)
    for name, text in dbds.items():
        (cache / f"{name}.dbd").write_text(text)
    return Ctx(**CTX_ARGS, home=tmp / "h")


def spell_names(rows, **kw):
    return make_wdc5(NAMES, rows, layout_hash=0xCAFEF00D, **kw)


def test_sparse_records_decode(tmp):
    rows = [{"ID": 3, "Name_lang": "Fireball"}, {"ID": 9, "Name_lang": "Frost Nova"}]
    assert list(db2.read(spell_names(rows, sparse=True), NAMES)) == rows
    # a sparse table whose ids sit in the id list, with an empty string, a signed value and a copy-table row
    fields = dbd.parse("COLUMNS\nint ID\nstring Name_lang\nint Rank\nfloat Speed\n\nLAYOUT 1\n$noninline,id$ID<32>\n"
                       "Name_lang\nRank<16>\nSpeed\n")[0].fields
    rows = [{"ID": 5, "Name_lang": "Bolt", "Rank": -2, "Speed": 0.5}, {"ID": 6, "Name_lang": "", "Rank": 7, "Speed": 2.0}]
    data = make_wdc5(fields, rows, sparse=True, copies=[(8, 5)])
    assert list(db2.read(data, fields)) == rows + [{"ID": 8, "Name_lang": "Bolt", "Rank": -2, "Speed": 0.5}]


def test_a_noninline_relation_field_reads_the_relationship_map_not_the_row_id(tmp):
    text = "COLUMNS\nint ID\nint Parent\nint Level\n\nLAYOUT 1\n$id$ID<32>\nLevel<32>\n$noninline,relation$Parent<32>\n"
    fields = dbd.parse(text)[0].fields
    rows = [{"ID": 1, "Parent": 500, "Level": 7}, {"ID": 2, "Parent": 77, "Level": 8}]
    assert list(db2.read(make_wdc5(fields, rows), fields)) == rows
    assert list(db2.read(make_wdc5(fields, rows, sparse=True), fields)) == rows


def test_export_writes_lua_table_keyed_by_id(tmp):
    ctx = home(tmp, SpellName=SPELL_NAME)
    src = FakeSource({"dbfilesclient/spellname.db2": spell_names([{"ID": 3, "Name_lang": "Fireball"}])})
    assert db2_export.write(src, tmp / "out", ctx) == 1
    assert lua_value(tmp / "out/db2/spellname/0.lua") == {3: {"Name_lang": "Fireball"}}


def test_chunks_split_at_ten_thousand_ids(tmp):
    ctx = home(tmp, SpellName=SPELL_NAME)
    names = {25: "A", 9999: "B", 10000: "C"}
    src = FakeSource({"dbfilesclient/spellname.db2": spell_names([{"ID": n, "Name_lang": t} for n, t in names.items()])})
    assert db2_export.write(src, tmp / "out", ctx) == 2
    assert lua_value(tmp / "out/db2/spellname/0.lua") == {25: {"Name_lang": "A"}, 9999: {"Name_lang": "B"}}
    assert lua_value(tmp / "out/db2/spellname/1.lua") == {10000: {"Name_lang": "C"}}
    assert sorted(p.name for p in (tmp / "out/db2/spellname").iterdir()) == ["0.lua", "1.lua"]


def test_a_rewrite_leaves_no_stale_chunk_or_single_file(tmp):
    ctx = home(tmp, SpellName=SPELL_NAME)
    (tmp / "out/db2/spellname").mkdir(parents=True)
    (tmp / "out/db2/spellname/7.lua").write_text("return {}")
    (tmp / "out/db2/spellname.lua").write_text("return {}")
    src = FakeSource({"dbfilesclient/spellname.db2": spell_names([{"ID": 3, "Name_lang": "Fireball"}])})
    db2_export.write(src, tmp / "out", ctx)
    assert [p.name for p in (tmp / "out/db2/spellname").iterdir()] == ["0.lua"]
    assert not (tmp / "out/db2/spellname.lua").exists()


def test_array_and_float_fields(tmp):
    fields = dbd.parse(SPELL_MISC)[0].fields
    row = {"ID": 4, "SpellID": 40, "SpellIconFileDataID": 1, "SchoolMask": 1, "Flags": [1, 2], "Speed": 0.5}
    rows = list(db2.read(make_wdc5(fields, [row], layout_hash=0xA5A5), fields))
    (tmp / "t.lua").write_text(db2_export.to_lua(rows, "SpellMisc", home(tmp)))
    assert lua_value(tmp / "t.lua") == {4: row}


def test_a_key_that_is_not_an_integer_is_skipped_and_noted_never_written_raw(tmp):
    ctx = home(tmp)  # a DBD that types ID or SpellID as a string would hand these keys to the writer
    rows = [{"ID": "1] = os.exit() --", "A": 1}, {"ID": True, "A": 3}, {"ID": 2, "A": 2}]
    (tmp / "t.lua").write_text(db2_export.to_lua(rows, "T", ctx))
    assert lua_value(tmp / "t.lua") == {2: {"ID": 2, "A": 2}}
    assert db2_export.r5_entries("SpellMisc", [{"ID": 1, "SpellID": "x"}], ctx) == []
    assert ctx.notes[0] == "db2: T: 2 rows without an integer key were skipped", ctx.notes
    assert ctx.notes[-1] == "db2: SpellMisc: 1 rows without an integer key were skipped", ctx.notes


def test_only_whitelisted_columns_are_written_and_a_missing_one_is_noted(tmp):
    ctx = home(tmp, Item=ITEM)  # no SubclassID, InventoryType: named in R5_COLUMNS, absent from this DBD
    fields = dbd.parse(ITEM)[0].fields
    row = {"ID": 6948, "ClassID": 15, "IconFileDataID": 134414, "Junk": 9}
    src = FakeSource({"dbfilesclient/item.db2": make_wdc5(fields, [row], layout_hash=0xB1)})
    assert db2_export.write(src, tmp / "out", ctx) == 1
    assert lua_value(tmp / "out/db2/item/0.lua") == {6948: {"ClassID": 15, "IconFileDataID": 134414}}
    for column in ("SubclassID", "InventoryType"):
        assert f"db2: Item: column {column} is not in the DBD, skipped" in ctx.notes, ctx.notes


def test_spellmisc_is_keyed_by_spell_id_and_repeats_are_counted(tmp):
    ctx = home(tmp, SpellMisc=SPELL_MISC)
    fields = dbd.parse(SPELL_MISC)[0].fields
    rows = [{"ID": 10, "SpellID": 133, "SpellIconFileDataID": 132266, "SchoolMask": 4, "Flags": [0, 0], "Speed": 0.0},
            {"ID": 11, "SpellID": 133, "SpellIconFileDataID": 1, "SchoolMask": 1, "Flags": [0, 0], "Speed": 0.0},
            {"ID": 12, "SpellID": 116, "SpellIconFileDataID": 135846, "SchoolMask": 16, "Flags": [0, 0], "Speed": 0.0}]  # fmt: skip
    src = FakeSource({"dbfilesclient/spellmisc.db2": make_wdc5(fields, rows, layout_hash=0xA5A5)})
    assert db2_export.write(src, tmp / "out", ctx) == 1
    assert lua_value(tmp / "out/db2/spellmisc/0.lua") == {
        133: {"SpellID": 133, "SpellIconFileDataID": 132266, "SchoolMask": 4},  # the lowest row ID wins
        116: {"SpellID": 116, "SpellIconFileDataID": 135846, "SchoolMask": 16},
    }
    assert "db2: SpellMisc: 1 rows repeat a SpellID and were dropped (the lowest ID wins)" in ctx.notes, ctx.notes


def test_missing_table_or_dbd_is_skipped_and_recorded(tmp):
    ctx = home(tmp, SpellName=SPELL_NAME)  # no SpellMisc.dbd in the cache, and no network
    misc = make_wdc5(dbd.parse(SPELL_MISC)[0].fields, [{"ID": 4, "SpellID": 4, "Flags": [0, 0]}], layout_hash=0xA5A5)
    src = FakeSource({"dbfilesclient/spellname.db2": spell_names([{"ID": 3, "Name_lang": "Fireball"}]),
                      "dbfilesclient/spellmisc.db2": misc})  # fmt: skip

    def fetch(name, cache, **kw):
        if name != "SpellName":
            raise OSError("offline")
        return SPELL_NAME

    real, dbd.fetch = dbd.fetch, fetch
    try:
        assert db2_export.write(src, tmp / "out", ctx) == 1  # SpellName only
    finally:
        dbd.fetch = real
    assert (tmp / "out/db2/spellname/0.lua").is_file() and not (tmp / "out/db2/spellmisc").exists()
    assert any("SpellMisc not read: offline" in n for n in ctx.notes), ctx.notes
    assert any("Item has no listfile entry" in n for n in ctx.notes), ctx.notes
    assert not any("SpellName" in n for n in ctx.notes), ctx.notes


def test_encrypted_section_rows_skipped_and_counted(tmp):
    ctx = home(tmp, SpellName=SPELL_NAME)
    data = spell_names([{"ID": 3, "Name_lang": "Fireball"}], locked_rows=4)
    assert db2_export.write(FakeSource({"dbfilesclient/spellname.db2": data}), tmp / "out", ctx) == 1
    assert lua_value(tmp / "out/db2/spellname/0.lua") == {3: {"Name_lang": "Fireball"}}
    assert "db2: SpellName: 4 rows lost to 1 encrypted sections" in ctx.notes, ctx.notes


TESTS = [
    test_sparse_records_decode,
    test_a_noninline_relation_field_reads_the_relationship_map_not_the_row_id,
    test_export_writes_lua_table_keyed_by_id,
    test_chunks_split_at_ten_thousand_ids,
    test_a_rewrite_leaves_no_stale_chunk_or_single_file,
    test_array_and_float_fields,
    test_a_key_that_is_not_an_integer_is_skipped_and_noted_never_written_raw,
    test_only_whitelisted_columns_are_written_and_a_missing_one_is_noted,
    test_spellmisc_is_keyed_by_spell_id_and_repeats_are_counted,
    test_missing_table_or_dbd_is_skipped_and_recorded,
    test_encrypted_section_rows_skipped_and_counted,
]
