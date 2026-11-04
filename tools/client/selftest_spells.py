"""Tests for the spell DB2 exports of the simulation (Task 5.1): SpellEffect (chunked, indexed by SpellID), SpellRange,
SpellCastTimes, SpellCooldowns, SpellPower, SpellRadius and SpellDuration; array columns; a column the DBD lacks."""

from tools.client import db2_export, dbd
from tools.client.fakes import FakeSource, lua_value, make_wdc5
from tools.client.selftest_r5 import home

BUILD = "BUILD 12.0.0.0-12.9.9.99999\n"
EFFECT_COLUMNS = (
    "ID SpellID EffectIndex Effect EffectAura EffectBasePoints EffectRadiusIndex[2] EffectMiscValue EffectTriggerSpell "
    "EffectAuraPeriod ImplicitTarget[2] DifficultyID"
).split()
RANGE_COLUMNS = "ID RangeMin[2] RangeMax[2]".split()


def dbd_text(columns, layout):
    """A DBD text declaring `columns` (`Name` or `Name[2]`) as 32-bit ints under LAYOUT `layout`."""
    declared, stored = "", ""
    for column in columns:
        name, _, size = column.partition("[")
        prefix = "$id$" if name == "ID" else ""
        declared += f"int {name}\n"
        stored += f"{prefix}{name}<32>{'[' + size if size else ''}\n"

    return f"COLUMNS\n{declared}\nLAYOUT {layout}\n{BUILD}{stored}"


def table_file(columns, rows, layout):
    text = dbd_text(columns, layout)

    return text, make_wdc5(dbd.parse(text)[0].fields, rows, layout_hash=int(layout, 16))


def effect_row(row_id, spell_id, index, effect, target, difficulty=0):
    row = {"ID": row_id, "SpellID": spell_id, "EffectIndex": index, "Effect": effect, "EffectAura": 0}
    row.update(EffectBasePoints=19, EffectRadiusIndex=[0, 0], EffectMiscValue=0, EffectTriggerSpell=0)
    row.update(EffectAuraPeriod=0, ImplicitTarget=[target, 0], DifficultyID=difficulty)
    return row


def export_fixture(tmp, drop=None, rename=None, extra=()):
    """Exports SpellEffect (rows 11 and 12 share SpellID 900001, `extra` adds rows) and SpellRange (row 5 reaches
    [40, 40]); returns (out dir, ctx). `drop` names a SpellEffect column the DBD lacks, `rename` maps a column to the
    name a newer layout gives it."""
    rename = rename or {}
    columns = [rename.get(c, c) for c in EFFECT_COLUMNS if c != drop]
    rows = [effect_row(11, 900001, 0, 2, 6), effect_row(12, 900001, 1, 6, 6), *extra]
    rows = [{rename.get(k, k): v for k, v in row.items() if k != drop} for row in rows]
    effect_dbd, effect_db2 = table_file(columns, rows, "0000E001")
    range_dbd, range_db2 = table_file(RANGE_COLUMNS, [{"ID": 5, "RangeMin": [0, 0], "RangeMax": [40, 40]}], "0000E002")
    ctx = home(tmp, SpellEffect=effect_dbd, SpellRange=range_dbd)
    source = FakeSource({"dbfilesclient/spelleffect.db2": effect_db2, "dbfilesclient/spellrange.db2": range_db2})
    db2_export.write(source, tmp / "out", ctx)

    return tmp / "out", ctx


def read_index(out, table, column, value):
    """The row IDs the chunked index file of `table`.`column` holds for `value`."""
    chunk = out / "db2" / "index" / f"{table}.{column}" / f"{value // db2_export.CHUNK}.lua"

    return lua_value(chunk)[value]


def test_spell_tables_export_with_spell_id_index(tmp):
    out, _ = export_fixture(tmp)
    effects = lua_value(out / "db2" / "spelleffect" / "0.lua")
    assert effects[11]["Effect"] == 2 and effects[11]["ImplicitTarget"] == [6, 0]
    assert sorted(read_index(out, "spelleffect", "spellid", 900001)) == [11, 12]
    assert lua_value(out / "db2" / "spellrange.lua")[5]["RangeMax"] == [40, 40]


def test_a_column_the_dbd_lacks_is_noted_not_fatal(tmp):
    _, ctx = export_fixture(tmp, drop="EffectMiscValue")
    assert any("EffectMiscValue is not in the DBD" in note for note in ctx.notes), ctx.notes


def test_the_difficulty_of_a_row_is_exported_and_a_layout_without_it_is_noted_not_fatal(tmp):
    out, _ = export_fixture(tmp / "retail", extra=[effect_row(13, 900001, 0, 2, 6, difficulty=1)])
    effects = lua_value(out / "db2" / "spelleffect" / "0.lua")
    assert [effects[11]["DifficultyID"], effects[13]["DifficultyID"]] == [0, 1]
    out, ctx = export_fixture(tmp / "classic", drop="DifficultyID")
    assert any("DifficultyID is not in the DBD" in note for note in ctx.notes), ctx.notes
    assert "DifficultyID" not in lua_value(out / "db2" / "spelleffect" / "0.lua")[11]


def test_a_newer_layout_with_float_base_points_still_exports_them(tmp):
    out, _ = export_fixture(tmp, rename={"EffectBasePoints": "EffectBasePointsF"})
    assert lua_value(out / "db2" / "spelleffect" / "0.lua")[11]["EffectBasePointsF"] == 19


def test_the_seven_spell_tables_are_exported_with_the_pinned_columns(tmp):
    tables = db2_export.WINDOW_TABLES
    assert tables["SpellEffect"]["chunked"] and tables["SpellEffect"]["index"] == ("SpellID",)
    assert tables["SpellCooldowns"]["index"] == ("SpellID",) and tables["SpellPower"]["index"] == ("SpellID",)
    assert tables["SpellRange"]["columns"] == ("ID", "RangeMin", "RangeMax")
    assert tables["SpellCastTimes"]["columns"] == ("ID", "Base")
    assert tables["SpellRadius"]["columns"] == ("ID", "Radius")
    assert tables["SpellDuration"]["columns"] == ("ID", "Duration")
    assert not any(tables[name]["chunked"] for name in tables if name.startswith("Spell") and name != "SpellEffect")


TESTS = [
    test_spell_tables_export_with_spell_id_index,
    test_a_column_the_dbd_lacks_is_noted_not_fatal,
    test_the_difficulty_of_a_row_is_exported_and_a_layout_without_it_is_noted_not_fatal,
    test_a_newer_layout_with_float_base_points_still_exports_them,
    test_the_seven_spell_tables_are_exported_with_the_pinned_columns,
]
