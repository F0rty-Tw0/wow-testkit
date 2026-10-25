"""Tests for the DBD parser and the WDC5 reader."""

from tools.client import db2, dbd
from tools.client.fakes import make_wdc5

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


TESTS = [
    test_wdc5_inline_and_bitpacked_fields,
    test_pallet_and_common_fields,
    test_string_table_strings,
    test_id_list_and_copy_table,
    test_dbd_block_picked_by_layout_hash,
]
