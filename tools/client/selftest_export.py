"""Tests for the DB2 export, the encrypted-section handling and GlobalStrings read from DB2."""

import io
import struct

from PIL import Image

from tools.client import art, db2, db2_export, dbd, paths, strings
from tools.client.extract import Ctx
from tools.client.fakes import FakeCasc, FakeSource, lua_value, make_wdc5
from tools.client.source import CascSource

CTX_ARGS = dict(flavor="retail", product="wow", build="70575", version="12.1.5.70575", locales=["enUS"])
GLOBAL_STRINGS = (
    "COLUMNS\nint ID\nstring BaseTag\nint Flags\nlocstring TagText_lang\n\nLAYOUT 0000000A\nBUILD 12.1.5.70575\n"
    "$noninline,id$ID<32>\nBaseTag\nTagText_lang\nFlags<32>\n"
)
SHEET = (
    "COLUMNS\nint ID\nint FileDataID\nint AtlasWidth\nint AtlasHeight\n\nLAYOUT 00000001\nBUILD 12.1.5.70575\n"
    "$id$ID<32>\nFileDataID<32>\nAtlasWidth<16>\nAtlasHeight<16>\n"
)
MEMBER = (
    "COLUMNS\nint ID\nstring CommittedName\nint UiTextureAtlasID\nint UiTextureAtlasElementID\nint CommittedLeft\n"
    "int CommittedRight\nint CommittedTop\nint CommittedBottom\nint OverrideWidth\nint OverrideHeight\n\n"
    "LAYOUT 00000002\nBUILD 12.1.5.70575\n$id$ID<32>\nCommittedName\nUiTextureAtlasID<16>\n"
    "UiTextureAtlasElementID<16>\nCommittedLeft<16>\nCommittedRight<16>\nCommittedTop<16>\nCommittedBottom<16>\n"
    "OverrideWidth<16>\nOverrideHeight<16>\n"
)
ELEMENT = "COLUMNS\nint ID\nstring Name\n\nLAYOUT 00000003\nBUILD 12.1.5.70575\n$id$ID<32>\nName\n"
TABLE = dbd.parse(GLOBAL_STRINGS)[0].fields


def seed(**texts):
    cache = paths.testkit_home() / "dbd"
    cache.mkdir(parents=True, exist_ok=True)
    for name, text in texts.items():
        (cache / f"{name}.dbd").write_text(text)


def global_strings(rows, **kw):
    return FakeSource({"dbfilesclient/globalstrings.db2": make_wdc5(TABLE, rows, layout_hash=0xA, **kw)})


def row(n, tag, text):
    return {"ID": n, "BaseTag": tag, "TagText_lang": text, "Flags": 1}


def test_strings_come_from_the_db2_when_there_is_no_lua(tmp):
    seed(GlobalStrings=GLOBAL_STRINGS)
    ctx = Ctx(**CTX_ARGS)
    src = global_strings([row(1, "TOOLTIP_UNIT_LEVEL", "Level %s"), row(2, "QUOTE", 'say \\"hi\\"\\n')], locked_rows=3)
    assert strings.write(src, tmp / "out", ctx) == 1
    assert lua_value(tmp / "out/strings/enUS.lua") == {"TOOLTIP_UNIT_LEVEL": "Level %s", "QUOTE": 'say "hi"\n'}
    assert ctx.notes == ["db2: GlobalStrings: 3 rows lost to 1 encrypted sections"], ctx.notes


def test_db2_text_escapes_are_decoded_and_other_text_kept(tmp):
    # retail 70575 TagText mixes forms: `Abandon \"%s\"?` and `%s says:\32` are escaped, `Day: "%s"` and `\` are not
    seed(GlobalStrings=GLOBAL_STRINGS)
    ctx = Ctx(**CTX_ARGS)
    src = global_strings([row(1, "Q", 'Abandon \\"%s\\"?'), row(2, "S", "%s says:\\32"), row(3, "N", "a\\nb\\\\c"),
                          row(4, "BARE", 'Day: "%s"'), row(5, "KEY", "\\"), row(6, "ODD", "C:\\Path \\999")])
    strings.write(src, tmp / "out", ctx)
    assert lua_value(tmp / "out/strings/enUS.lua") == {
        "Q": 'Abandon "%s"?', "S": "%s says: ", "N": "a\nb\\c", "BARE": 'Day: "%s"', "KEY": "\\", "ODD": "C:\\Path \\999"}
    assert ctx.notes == [], ctx.notes


def test_db2_decimal_escapes_are_bytes_read_as_utf8(tmp):
    assert strings.unescape(r"caf\195\169 \226\128\148") == "café —"  # a run of \ddd is one byte string
    assert strings.unescape(r"\233t\0651\256") == "étA1\\256"  # not UTF-8: one char per byte; greedy; too large


def test_a_globalstrings_lua_wins_over_the_db2(tmp):
    seed(GlobalStrings=GLOBAL_STRINGS)
    src = global_strings([row(1, "FROM_DB2", "x")])
    src.files["interface/framexml/globalstrings.lua"] = b'FROM_LUA = "y"'
    strings.write(src, tmp / "out", Ctx(**CTX_ARGS))
    assert lua_value(tmp / "out/strings/enUS.lua") == {"FROM_LUA": "y"}


def test_missing_db2_or_dbd_is_a_note_not_an_error(tmp):
    ctx = Ctx(**CTX_ARGS)
    assert strings.write(FakeSource({}), tmp / "out", ctx) == 0
    assert any("GlobalStrings has no listfile entry" in n for n in ctx.notes), ctx.notes
    ctx = Ctx(**CTX_ARGS)

    def offline(*args, **kwargs):
        raise OSError("offline")

    real, dbd.fetch = dbd.fetch, offline
    try:
        assert strings.write(global_strings([row(1, "A", "b")]), tmp / "out", ctx) == 0
    finally:
        dbd.fetch = real
    assert any("GlobalStrings not read: offline" in n for n in ctx.notes), ctx.notes
    assert not (tmp / "out/strings").exists()


def test_locked_sections_yield_no_rows_and_are_counted(tmp):
    data = make_wdc5(TABLE, [row(1, "A", "a")], layout_hash=0xA, locked_rows=2)
    head = db2.header(data)
    assert len(head.sections) == 2 and db2.lost_rows(head) == 2
    assert [r["BaseTag"] for r in db2.read(data, TABLE)] == ["A"]


def test_stale_dbd_cache_is_refreshed_once(tmp):
    fetched = []

    def fetch(name, cache, opener=None, refresh=False):
        fetched.append(refresh)
        return GLOBAL_STRINGS if refresh else GLOBAL_STRINGS.replace("0000000A", "0000000B").replace("12.1.5", "12.0.0")

    real, dbd.fetch = dbd.fetch, fetch
    ctx = Ctx(**CTX_ARGS)
    try:
        rows = db2_export.read_table(global_strings([row(1, "A", "b")]), "GlobalStrings", ctx)
    finally:
        dbd.fetch = real
    assert fetched == [False, True] and rows[0]["BaseTag"] == "A", (fetched, ctx.notes)


def test_dbd_fetch_caches_and_sends_no_personal_headers(tmp):
    seen = []

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def read(self):
            return b"COLUMNS\nint ID\n"

    def opener(request):
        seen.append((request.full_url, dict(request.header_items())))
        return Response()

    assert dbd.fetch("Foo", tmp / "cache", opener=opener) == "COLUMNS\nint ID\n"
    assert dbd.fetch("Foo", tmp / "cache", opener=opener) == "COLUMNS\nint ID\n"
    assert len(seen) == 1 and seen[0][0].endswith("/definitions/Foo.dbd"), seen
    assert seen[0][1] == {"User-agent": "wow-testkit"}, seen
    try:
        dbd.fetch("../evil", tmp / "cache", opener=opener)
    except dbd.DbdError:
        pass
    else:
        raise AssertionError("a path in the table name must be refused")


def test_db2_export_writes_tables_and_atlas_lua(tmp):
    seed(UiTextureAtlas=SHEET, UiTextureAtlasMember=MEMBER, UiTextureAtlasElement=ELEMENT)
    sheet, member, element = (dbd.parse(text)[0].fields for text in (SHEET, MEMBER, ELEMENT))
    sheet_row = {"ID": 5, "FileDataID": 900, "AtlasWidth": 256, "AtlasHeight": 128}
    member_row = {"ID": 1, "CommittedName": "lower", "UiTextureAtlasID": 5, "UiTextureAtlasElementID": 40,
                  "CommittedLeft": 0, "CommittedRight": 64, "CommittedTop": 0, "CommittedBottom": 32,
                  "OverrideWidth": 0, "OverrideHeight": 0}  # fmt: skip
    src = FakeSource({
        "dbfilesclient/uitextureatlas.db2": make_wdc5(sheet, [sheet_row], layout_hash=1),
        "dbfilesclient/uitextureatlasmember.db2": make_wdc5(member, [member_row], layout_hash=2),
        "dbfilesclient/uitextureatlaselement.db2": make_wdc5(element, [{"ID": 40, "Name": "Tooltip-Frame"}], layout_hash=3),
    })  # fmt: skip
    ctx = Ctx(**CTX_ARGS)
    assert db2_export.write(src, tmp / "out", ctx) == 4  # the R5 and window tables are absent here: skipped and noted
    absent = (*db2_export.R5_TABLES, *db2_export.WINDOW_TABLES)
    assert ctx.notes == [f"db2: {name} has no listfile entry in this client" for name in absent], ctx.notes
    assert lua_value(tmp / "out/db2/uitextureatlas.lua") == {5: sheet_row}
    assert lua_value(tmp / "out/db2/uitextureatlaselement.lua") == {40: {"ID": 40, "Name": "Tooltip-Frame"}}
    assert lua_value(tmp / "out/atlas.lua") == {
        "tooltip-frame": {"name": "Tooltip-Frame", "file": 900, "width": 64, "height": 32, "left": 0, "right": 0.25,
                          "top": 0, "bottom": 0.25}  # fmt: skip
    }


def test_read_id_needs_no_listfile_name_and_the_dbd_cache_lives_under_home(tmp):
    source = CascSource(FakeCasc({7: b"bytes"}), {}, ["enUS"])
    assert source.read_id(7) == b"bytes" and source.read_id(8) is None and source.paths() == []
    assert db2_export.dbd_dir(Ctx(**CTX_ARGS, home=tmp / "h")) == tmp / "h" / "dbd"
    assert db2_export.dbd_dir(Ctx(**CTX_ARGS)) == paths.testkit_home() / "dbd"


def test_raw_bgra_blp_decodes(tmp):
    pixels = bytes([0, 0, 255, 255, 255, 0, 0, 128] * 2)  # BGRA: red, then half-transparent blue; 2x2 over two rows
    head = b"BLP2" + struct.pack("<I4B", 1, 3, 8, 0, 0) + struct.pack("<2I", 2, 2)
    data = head + struct.pack("<16I", 148, *[0] * 15) + struct.pack("<16I", len(pixels), *[0] * 15) + bytes(1024)
    data = data[:148] + pixels
    image = Image.open(io.BytesIO(art.decode_to_png(data))).convert("RGBA")
    assert image.size == (2, 2) and image.getpixel((0, 0)) == (255, 0, 0, 255) and image.getpixel((1, 0)) == (0, 0, 255, 128)


def test_bitpacked_unaligned_signed_and_float_fields(tmp):
    text = "COLUMNS\nint ID\nint P\nint Q\nfloat F\nint Arr\n\nLAYOUT 1\n$id$ID<32>\nP<5>\nQ<11>\nF\nArr<16>[3]\n"
    fields = dbd.parse(text)[0].fields
    rows = [{"ID": 1, "P": 9, "Q": -100, "F": 1.5, "Arr": [1, -2, 3]}]
    data = make_wdc5(fields, rows, compression={"P": "bitpacked", "Q": "signed"})
    assert list(db2.read(data, fields)) == rows


TESTS = [
    test_strings_come_from_the_db2_when_there_is_no_lua,
    test_a_globalstrings_lua_wins_over_the_db2,
    test_db2_text_escapes_are_decoded_and_other_text_kept,
    test_db2_decimal_escapes_are_bytes_read_as_utf8,
    test_missing_db2_or_dbd_is_a_note_not_an_error,
    test_locked_sections_yield_no_rows_and_are_counted,
    test_stale_dbd_cache_is_refreshed_once,
    test_dbd_fetch_caches_and_sends_no_personal_headers,
    test_db2_export_writes_tables_and_atlas_lua,
    test_read_id_needs_no_listfile_name_and_the_dbd_cache_lives_under_home,
    test_raw_bgra_blp_decodes,
    test_bitpacked_unaligned_signed_and_float_fields,
]
