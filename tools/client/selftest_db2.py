"""Tests for the DBD parser, the WDC5 reader and the atlas tables built from them."""

from PIL import Image

from tools.client import art, atlas, db2, dbd
from tools.client.fakes import FakeSource, make_blp, make_wdc5

FIELDS = dbd.parse(
    "COLUMNS\nint ID\nint A\nint B\nstring Name_lang\n\nLAYOUT DEADBEEF\nBUILD 12.0.0.0-12.9.9.99999\n"
    "$id$ID<32>\nA<16>\nB<8>\nName_lang\n"
)[0].fields
NONINLINE = dbd.parse(
    "COLUMNS\nint ID\nint A\nstring Name_lang\n\nLAYOUT 1\n$noninline,id$ID<32>\nA<32>\nName_lang\n"
)[0].fields


def test_wdc5_inline_and_bitpacked_fields(tmp):
    data = make_wdc5(FIELDS, [{"ID": 7, "A": 513, "B": 9, "Name_lang": "x"}], layout_hash=0xDEADBEEF)
    assert db2.header(data).layout_hash == 0xDEADBEEF
    assert list(db2.read(data, FIELDS)) == [{"ID": 7, "A": 513, "B": 9, "Name_lang": "x"}]
    packed = make_wdc5(FIELDS, [{"ID": 7, "A": 513, "B": -3, "Name_lang": ""}], compression={"A": "bitpacked", "B": "signed"})
    assert list(db2.read(packed, FIELDS)) == [{"ID": 7, "A": 513, "B": -3, "Name_lang": ""}]


def test_pallet_and_common_fields(tmp):
    rows = [{"ID": n, "A": a, "B": b, "Name_lang": ""} for n, (a, b) in enumerate([(513, 5), (700, 0), (513, 6)], 1)]
    data = make_wdc5(FIELDS, rows, compression={"A": "pallet", "B": "common"})
    assert list(db2.read(data, FIELDS)) == rows


def test_string_table_strings(tmp):
    rows = [{"ID": 1, "A": 0, "B": 0, "Name_lang": "alpha"}, {"ID": 2, "A": 0, "B": 0, "Name_lang": "beta"},
            {"ID": 3, "A": 0, "B": 0, "Name_lang": "alpha"}]  # fmt: skip
    data = make_wdc5(FIELDS, rows)
    assert [row["Name_lang"] for row in db2.read(data, FIELDS)] == ["alpha", "beta", "alpha"]


def test_id_list_and_copy_table(tmp):
    row = {"ID": 7, "A": 11, "Name_lang": "seven"}
    data = make_wdc5(NONINLINE, [row], copies=[(8, 7)])
    assert list(db2.read(data, NONINLINE)) == [row, {**row, "ID": 8}]


def test_dbd_block_picked_by_layout_hash(tmp):
    text = (
        "COLUMNS\nint ID\nint A\nint B\n\n"
        "LAYOUT 11111111\nBUILD 12.1.5.70575\n$id$ID<32>\nA<32>\n\n"
        "LAYOUT 22222222\nBUILD 12.0.0.1-12.0.9.9\n$id$ID<32>\nB<32>\n"
    )
    blocks = dbd.parse(text)
    assert [f.name for f in dbd.pick(blocks, 0x22222222, "12.1.5.70575")] == ["ID", "B"]
    assert [f.name for f in dbd.pick(blocks, 0x99999999, "12.1.5.70575")] == ["ID", "A"]
    assert [f.name for f in dbd.pick(blocks, 0x99999999, "12.0.5.1")] == ["ID", "B"]


def test_atlas_names_join_member_to_sheet_coords(tmp):
    sheets = {5: {"ID": 5, "FileDataID": 900, "AtlasWidth": 256, "AtlasHeight": 128}}
    members = {1: {"ID": 1, "UiTextureAtlasID": 5, "UiTextureAtlasElementID": 40, "CommittedName": "lower",
                   "CommittedLeft": 0, "CommittedRight": 64, "CommittedTop": 0, "CommittedBottom": 32,
                   "OverrideWidth": 0, "OverrideHeight": 0}}  # fmt: skip
    elements = {40: {"ID": 40, "Name": "Tooltip-Frame"}}
    assert atlas.build(sheets, members, elements) == {
        "tooltip-frame": {"name": "Tooltip-Frame", "file": 900, "width": 64, "height": 32,
                          "left": 0, "right": 0.25, "top": 0, "bottom": 0.25}  # fmt: skip
    }
    elements.clear()  # no Element row: the member's own name is used
    assert list(atlas.build(sheets, members, elements)) == ["lower"]


def test_atlas_crop_writes_the_member_rect_png(tmp):
    ex = tmp / "ex"
    ex.mkdir()
    sheet = Image.new("RGBA", (256, 128), (0, 0, 255, 255))
    sheet.paste((255, 0, 0, 255), (0, 0, 64, 32))
    import io

    out = io.BytesIO()
    sheet.save(out, format="PNG")
    src = FakeSource({"interface/sheet.png": out.getvalue()}, ids={"interface/sheet.png": 900})
    (ex / "atlas.lua").write_text(
        'return { ["tooltip-frame"] = { name = "Tooltip-Frame", file = 900, width = 64, height = 32,'
        " left = 0, right = 0.25, top = 0, bottom = 0.25 } }\n"
    )
    path = atlas.crop(ex, "Tooltip-Frame", source=src)
    assert path == ex / "art/atlas/tooltip-frame.png"
    image = Image.open(path).convert("RGBA")
    assert image.size == (64, 32) and image.getpixel((0, 0)) == (255, 0, 0, 255)
    assert atlas.crop(ex, "no-such-atlas", source=src) is None


def test_atlas_crop_scales_each_side_by_its_own_axis(tmp):
    ex = tmp / "ex"
    ex.mkdir()
    sheet = Image.new("RGBA", (256, 128), (0, 0, 255, 255))  # wide sheet, so a side scaled by the other axis is off
    sheet.paste((255, 0, 0, 255), (64, 32, 128, 96))
    sheet.paste((0, 255, 0, 255), (64, 32, 65, 33))  # marks the rect's top-left pixel
    src = FakeSource({"interface/sheet.png": art.to_png_bytes(sheet)}, ids={"interface/sheet.png": 900})
    (ex / "atlas.lua").write_text(
        'return { ["offset"] = { name = "Offset", file = 900, width = 64, height = 64,'
        " left = 0.25, right = 0.5, top = 0.25, bottom = 0.75 } }\n"
    )
    image = Image.open(atlas.crop(ex, "Offset", source=src)).convert("RGBA")
    assert image.size == (64, 64), image.size
    assert image.getpixel((0, 0)) == (0, 255, 0, 255) and image.getpixel((63, 63)) == (255, 0, 0, 255)


TESTS = [
    test_wdc5_inline_and_bitpacked_fields,
    test_pallet_and_common_fields,
    test_string_table_strings,
    test_id_list_and_copy_table,
    test_dbd_block_picked_by_layout_hash,
    test_atlas_names_join_member_to_sheet_coords,
    test_atlas_crop_writes_the_member_rect_png,
    test_atlas_crop_scales_each_side_by_its_own_axis,
]
