"""Tests for the spell and item DB2 exports (R5): sparse records, array and float fields, skipped and locked tables."""

from tools.client import db2, db2_export, dbd
from tools.client.extract import Ctx
from tools.client.fakes import FakeSource, lua_value, make_wdc5

CTX_ARGS = dict(flavor="retail", product="wow", build="70575", version="12.1.5.70575", locales=["enUS"])
SPELL_NAME = "COLUMNS\nint ID\nlocstring Name_lang\n\nLAYOUT CAFEF00D\nBUILD 12.0.0.0-12.9.9.99999\n$id$ID<32>\nName_lang\n"
SPELL_MISC = (
    "COLUMNS\nint ID\nint Flags\nfloat Speed\n\nLAYOUT 0000A5A5\nBUILD 12.0.0.0-12.9.9.99999\n"
    "$id$ID<32>\nFlags<32>[2]\nSpeed\n"
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


def test_export_writes_lua_table_keyed_by_id(tmp):
    ctx = home(tmp, SpellName=SPELL_NAME)
    src = FakeSource({"dbfilesclient/spellname.db2": spell_names([{"ID": 3, "Name_lang": "Fireball"}])})
    assert db2_export.write(src, tmp / "out", ctx) == 1
    assert lua_value(tmp / "out/db2/spellname.lua") == {3: {"ID": 3, "Name_lang": "Fireball"}}


def test_array_and_float_fields(tmp):
    ctx = home(tmp, SpellMisc=SPELL_MISC)
    fields = dbd.parse(SPELL_MISC)[0].fields
    row = {"ID": 4, "Flags": [1, 2], "Speed": 0.5}
    src = FakeSource({"dbfilesclient/spellmisc.db2": make_wdc5(fields, [row], layout_hash=0xA5A5)})
    db2_export.write(src, tmp / "out", ctx)
    assert lua_value(tmp / "out/db2/spellmisc.lua") == {4: {"ID": 4, "Flags": [1, 2], "Speed": 0.5}}


def test_missing_table_or_dbd_is_skipped_and_recorded(tmp):
    ctx = home(tmp, SpellName=SPELL_NAME)  # no SpellMisc.dbd in the cache, and no network
    misc = make_wdc5(dbd.parse(SPELL_MISC)[0].fields, [{"ID": 4, "Flags": [1, 2], "Speed": 0.5}], layout_hash=0xA5A5)
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
    assert (tmp / "out/db2/spellname.lua").is_file() and not (tmp / "out/db2/spellmisc.lua").exists()
    assert any("SpellMisc not read: offline" in n for n in ctx.notes), ctx.notes
    assert any("Item has no listfile entry" in n for n in ctx.notes), ctx.notes
    assert not any("SpellName" in n for n in ctx.notes), ctx.notes


def test_encrypted_section_rows_skipped_and_counted(tmp):
    ctx = home(tmp, SpellName=SPELL_NAME)
    data = spell_names([{"ID": 3, "Name_lang": "Fireball"}], locked_rows=4)
    assert db2_export.write(FakeSource({"dbfilesclient/spellname.db2": data}), tmp / "out", ctx) == 1
    assert lua_value(tmp / "out/db2/spellname.lua") == {3: {"ID": 3, "Name_lang": "Fireball"}}
    assert "db2: SpellName: 4 rows lost to 1 encrypted sections" in ctx.notes, ctx.notes


TESTS = [
    test_sparse_records_decode,
    test_export_writes_lua_table_keyed_by_id,
    test_array_and_float_fields,
    test_missing_table_or_dbd_is_skipped_and_recorded,
    test_encrypted_section_rows_skipped_and_counted,
]
