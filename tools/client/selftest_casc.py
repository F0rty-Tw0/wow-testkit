"""Tests for the pure-Python CASC reader, over synthetic local stores built by fakes.write_install."""

import contextlib
import io
import struct

from tools.client import casc, casc_blte, casc_index, fakes, probe
from tools.client.source import CascSource
from tools.client.fakes import DEDE, ENUS, HIGH_RES, LOW_VIOLENCE, NO_NAME_HASH

LUA = b"-- lua\nlocal x = 1\n" * 40
BLP = b"BLP2" + bytes(range(256)) * 4
DB2 = b"WDC5" + b"\x01\x02" * 300
TTF = b"\x00\x01\x00\x00" + b"glyf" * 200
FILES = {10: (LUA, "-"), 20: (BLP, "NZ"), 30: (DB2, "Z"), 40: (TTF, "ZNZ"), 50: (b"secret" * 20, "ZE")}
NAMES = {
    10: "interface/addons/blizzard_a/a.lua",
    20: "interface/buttons/white8x8.blp",
    30: "dbfilesclient/uitextureatlas.db2",
    40: "fonts/frizqt__.ttf",
}


def install(tmp, files=FILES, **kw):
    return fakes.write_install(tmp / "wow", {"wow": [(ENUS, 0, files)]}, **kw)


def test_blte_decodes_headerless_and_chunked_n_z_blocks(tmp):
    assert casc_blte.decode(fakes.blte(LUA, "N", headerless=True)) == LUA
    assert casc_blte.decode(fakes.blte(LUA, "Z", headerless=True)) == LUA
    assert casc_blte.decode(fakes.blte(TTF, "ZNZ")) == TTF


def test_blte_encrypted_blocks_are_unreadable_naming_count_and_keys(tmp):
    try:
        casc_blte.decode(fakes.blte(LUA, "ZEE"))
    except casc_blte.Unreadable as err:
        assert "2 of 3 blocks encrypted" in str(err) and "aaaaaaaaaaaaaaaa" in str(err)
        return
    raise AssertionError("expected Unreadable")


def test_blte_zero_fills_encrypted_blocks_only_when_asked_and_some_block_is_readable(tmp):
    holes = []
    data = casc_blte.decode(fakes.blte(b"A" * 10 + b"B" * 10, "ZE"), holes)
    assert data == b"A" * 10 + b"\0" * 10 and holes == ["aaaaaaaaaaaaaaaa"]
    try:
        casc_blte.decode(fakes.blte(b"C" * 20, "EE"), [])
    except casc_blte.Unreadable:
        return
    raise AssertionError("expected Unreadable when every block is encrypted")


def test_store_reads_files_through_root_encoding_index_and_archive(tmp):
    store = casc.open_store(install(tmp), "wow")
    try:
        assert {fid: store.read(fid) for fid in (10, 20, 30, 40)} == {10: LUA, 20: BLP, 30: DB2, 40: TTF}
        assert sorted(store.file_ids()) == sorted(FILES)
    finally:
        store.close()


def test_store_reads_a_partly_encrypted_file_as_none_by_default(tmp):
    store = casc.open_store(install(tmp), "wow")
    try:
        assert store.read(50) is None
        assert "id 50" in store.last_error and "1 of 2 blocks encrypted" in store.last_error
        assert "aaaaaaaaaaaaaaaa" in store.last_error
        assert store.read(10) == LUA and store.last_error is None
    finally:
        store.close()


def test_store_zero_fills_a_partly_encrypted_file_when_partial(tmp):
    store = casc.open_store(install(tmp), "wow")
    try:
        data = store.read(50, partial=True)
        assert data == b"secret" * 10 + b"\0" * 60  # Z block intact, E block zeros of its table size
        assert "1 encrypted block zero-filled" in store.last_error
    finally:
        store.close()


def test_store_returns_none_for_fully_encrypted_even_when_partial_and_for_unknown_ids(tmp):
    store = casc.open_store(install(tmp, files={**FILES, 60: (b"x" * 20, "EE")}), "wow")
    try:
        assert store.read(60, partial=True) is None and "2 of 2 blocks encrypted" in store.last_error
        assert store.read(99) is None and "not in root" in store.last_error
    finally:
        store.close()


def test_source_names_what_the_store_holds_and_forwards_partial(tmp):
    store = casc.open_store(install(tmp), "wow")
    try:
        names = {10: "interface/addons/blizzard_a/a.lua", 50: "db/x.db2", 999: "gone/not-in-store.lua"}
        source = CascSource(store, names, ["enUS"])
        assert source.paths() == ["db/x.db2", "interface/addons/blizzard_a/a.lua"]
        assert source.file_id("DB\\X.db2") == 50 and source.file_id("gone/not-in-store.lua") is None
        assert source.read("interface/addons/blizzard_a/a.lua") == LUA and source.read("nope") is None
        assert source.read("db/x.db2") is None  # an encrypted block: unreadable unless the caller asks for partial
        assert source.read("db/x.db2", partial=True) == b"secret" * 10 + b"\0" * 60
    finally:
        store.close()


def test_store_opens_the_row_of_the_requested_product(tmp):
    inst = fakes.write_install(tmp / "wow", {"wow": [(ENUS, 0, {1: (b"retail", "N")})],
                                             "wowf": [(ENUS, 0, {1: (b"forever", "Z")})]})
    for product, want in (("wow", b"retail"), ("wowf", b"forever")):
        store = casc.open_store(inst, product)
        assert store.read(1) == want
        store.close()


def test_unknown_product_is_an_error_naming_it(tmp):
    try:
        casc.open_store(install(tmp), "wow_classic_era")
    except casc.CascError as err:
        assert "wow_classic_era" in str(err)
        return
    raise AssertionError("expected CascError")


def test_root_prefers_enus_and_skips_low_violence_and_other_locales(tmp):
    blocks = [
        (DEDE, 0, {1: (b"de", "N"), 3: (b"de only", "N")}),
        (ENUS, LOW_VIOLENCE, {1: (b"low", "N")}),
        (ENUS | DEDE, 0, {1: (b"en", "N"), 2: (b"shared", "N")}),
        (0xFFFFFFFF, NO_NAME_HASH, {4: (b"unnamed", "N")}),
    ]
    store = casc.open_store(fakes.write_install(tmp / "wow", {"wow": blocks}), "wow")
    try:
        assert [store.read(fid) for fid in (1, 2, 4)] == [b"en", b"shared", b"unnamed"]
        assert sorted(store.file_ids()) == [1, 2, 4]
    finally:
        store.close()


def test_root_header_variants_read_alike(tmp):
    for version in (0, 1, 2):
        store = casc.open_store(install(tmp / str(version), root_version=version), "wow")
        try:
            assert store.read(30) == DB2, version
        finally:
            store.close()


def test_the_latest_index_version_of_each_bucket_wins(tmp):
    store = casc.open_store(install(tmp, stale_index=True), "wow")
    try:
        assert store.read(20) == BLP
    finally:
        store.close()


def test_records_with_a_blank_header_are_read(tmp):
    store = casc.open_store(install(tmp, zero_headers=True), "wow")
    try:
        assert {fid: store.read(fid) for fid in (10, 20, 30, 40)} == {10: LUA, 20: BLP, 30: DB2, 40: TTF}
    finally:
        store.close()


def storage_over(tmp, archive, entries, shift=0):
    """LocalStorage over one data.000 and the .idx files for `entries` [(ekey, offset, size)], each entry filed
    `shift` buckets away from its own."""
    data_dir = tmp / "data"
    data_dir.mkdir(parents=True)
    (data_dir / "data.000").write_bytes(archive)
    filed = [((fakes.bucket_of(ekey) + shift) % 16, (ekey[:9], 0, offset, size)) for ekey, offset, size in entries]
    for bucket in {bucket for bucket, _ in filed}:
        mine = [entry for b, entry in filed if b == bucket]
        (data_dir / f"{bucket:02x}00000001.idx").write_bytes(fakes.index_file(bucket, mine))
    return casc_index.LocalStorage(data_dir)


def test_an_entry_filed_in_another_bucket_is_still_found(tmp):
    wanted = fakes.blte(b"wanted", "N")
    ekey = fakes.ekey_of(wanted)
    storage = storage_over(tmp, ekey[::-1] + struct.pack("<I", 30 + len(wanted)) + bytes(10) + wanted,
                           [(ekey, 0, 30 + len(wanted))], shift=1)
    try:
        assert storage.read(ekey) == wanted
    finally:
        storage.close()


def test_a_record_is_read_by_hash_when_its_header_is_garbage_or_absent(tmp):
    wanted = fakes.blte(b"wanted", "Z")
    ekey = fakes.ekey_of(wanted)
    for sub, entry in (("header", (ekey, 0, 30 + len(wanted))), ("alias", (ekey, 30, len(wanted)))):
        storage = storage_over(tmp / sub, b"\x5a" * 30 + wanted, [entry])
        try:
            assert storage.read(ekey) == wanted, sub
        finally:
            storage.close()


def test_a_record_whose_header_and_blte_both_miss_the_ekey_is_rejected(tmp):
    other = fakes.blte(b"other", "Z")
    wanted = fakes.ekey_of(fakes.blte(b"wanted", "Z"))
    storage = storage_over(tmp, bytes(30) + other, [(wanted, 0, 30 + len(other)), (wanted, 30, len(other))])
    try:
        assert storage.read(wanted) is None
    finally:
        storage.close()


def test_root_ranks_high_res_texture_blocks_last(tmp):
    blocks = [(ENUS, HIGH_RES, {1: (b"hi", "N"), 2: (b"hi only", "N")}), (ENUS, 0, {1: (b"lo", "N")})]
    store = casc.open_store(fakes.write_install(tmp / "wow", {"wow": blocks}), "wow")
    try:
        assert [store.read(1), store.read(2)] == [b"lo", b"hi only"]
    finally:
        store.close()


def test_store_writes_nothing_under_the_install(tmp):
    inst = install(tmp)
    before = sorted((p.relative_to(inst).as_posix(), p.stat().st_mtime_ns) for p in inst.rglob("*"))
    store = casc.open_store(inst, "wow")
    store.read(40)
    store.close()
    assert sorted((p.relative_to(inst).as_posix(), p.stat().st_mtime_ns) for p in inst.rglob("*")) == before


def run_probe_cli(tmp, files):
    inst = install(tmp, files)
    lf = tmp / "lf.csv"
    lf.write_text("".join(f"{fid};{name}\n" for fid, name in NAMES.items()))
    out = io.StringIO()
    argv = ["--candidate", "casc", "--install", str(inst), "--products", "wow", "--listfile", str(lf)]
    with contextlib.redirect_stdout(out):
        code = probe.main(argv)
    return code, out.getvalue().splitlines()


def test_probe_cli_runs_the_casc_candidate(tmp):
    code, lines = run_probe_cli(tmp, FILES)
    assert code == 0, lines
    assert [line.split()[:3] for line in lines] == [["PASS", "wow", name] for name in ("lua", "blp", "db2", "ttf")]


def test_probe_zero_fills_only_the_db2_and_says_so(tmp):
    code, lines = run_probe_cli(tmp / "db2", {**FILES, 30: (DB2, "ZE")})
    assert code == 0 and "1 encrypted block zero-filled" in lines[2], lines
    code, lines = run_probe_cli(tmp / "blp", {**FILES, 20: (BLP, "ZE")})
    assert code == 1 and lines[1].startswith("FAIL wow blp") and "1 of 2 blocks encrypted" in lines[1], lines


TESTS = [
    test_blte_decodes_headerless_and_chunked_n_z_blocks,
    test_blte_encrypted_blocks_are_unreadable_naming_count_and_keys,
    test_blte_zero_fills_encrypted_blocks_only_when_asked_and_some_block_is_readable,
    test_store_reads_files_through_root_encoding_index_and_archive,
    test_store_reads_a_partly_encrypted_file_as_none_by_default,
    test_store_zero_fills_a_partly_encrypted_file_when_partial,
    test_store_returns_none_for_fully_encrypted_even_when_partial_and_for_unknown_ids,
    test_source_names_what_the_store_holds_and_forwards_partial,
    test_store_opens_the_row_of_the_requested_product,
    test_unknown_product_is_an_error_naming_it,
    test_root_prefers_enus_and_skips_low_violence_and_other_locales,
    test_root_header_variants_read_alike,
    test_the_latest_index_version_of_each_bucket_wins,
    test_records_with_a_blank_header_are_read,
    test_a_record_is_read_by_hash_when_its_header_is_garbage_or_absent,
    test_a_record_whose_header_and_blte_both_miss_the_ekey_is_rejected,
    test_an_entry_filed_in_another_bucket_is_still_found,
    test_root_ranks_high_res_texture_blocks_last,
    test_store_writes_nothing_under_the_install,
    test_probe_cli_runs_the_casc_candidate,
    test_probe_zero_fills_only_the_db2_and_says_so,
]
