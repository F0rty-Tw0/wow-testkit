"""In-memory stand-ins for the client store, and a tiny synthetic CASC install, so self-tests never touch an install."""

import hashlib
import struct
import zlib
from pathlib import Path

HIGH_RES = 0x1
ENUS = 0x2
DEDE = 0x20
LOW_VIOLENCE = 0x80
NO_NAME_HASH = 0x10000000


class FakeCasc:
    """CascStore over a dict of fileID -> bytes."""

    last_error = None

    def __init__(self, files):
        self.files = dict(files)
        self.closed = False

    def read(self, file_id, partial=False):
        return self.files.get(file_id)

    def file_ids(self):
        return list(self.files)

    def close(self):
        self.closed = True


class FakeSource:
    """extract.Source over {path: bytes}; `ids` gives paths a fileID (default: their order, from 1)."""

    def __init__(self, files, ids=None, locales=("enUS",)):
        self.files = {path.lower(): data for path, data in files.items()}
        self.ids = ids if ids is not None else {path: n for n, path in enumerate(self.files, 1)}
        self.locales = list(locales)

    def paths(self):
        return sorted(self.files)

    def read(self, path, partial=False):
        return self.files.get(path.lower())

    def file_id(self, path):
        return self.ids.get(path.lower())


def make_install(root, build_info):
    """A bare install folder holding only `.build.info`; returns it."""
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    (root / ".build.info").write_text(build_info, newline="\n")
    return root


def write_listfile(tmp, names):
    """<tmp>/listfile.csv with `id;path` lines for {fileID: path}; returns its path."""
    path = Path(tmp) / "listfile.csv"
    path.write_text("".join(f"{file_id};{name}\n" for file_id, name in sorted(names.items())), newline="\n")
    return path


def lua_value(path):
    """The table a Lua file returns, as dicts and lists (an empty table is {}), loaded with lupa."""
    import lupa

    def convert(value):
        if not lupa.lua_type(value):
            return value
        if len(value) and list(value.keys()) == list(range(1, len(value) + 1)):
            return [convert(item) for item in value.values()]
        return {key: convert(item) for key, item in value.items()}

    return convert(lupa.LuaRuntime().execute(Path(path).read_text(encoding="utf-8")))


def md5(data):
    return hashlib.md5(data).digest()


def blte_block(mode, part):
    if mode == "N":
        return b"N" + part
    if mode == "Z":
        return b"Z" + zlib.compress(part)
    if mode == "E":
        return b"E" + bytes([8]) + b"\xaa" * 8 + bytes([4]) + b"\xbb" * 4 + b"S" + part
    raise ValueError(mode)


def blte(data, modes="N", headerless=False):
    """BLTE bytes, one block per letter of `modes` (N, Z or E); `headerless` writes a single block with headerSize 0."""
    if headerless:
        return b"BLTE" + struct.pack(">I", 0) + blte_block(modes, data)
    step = -(-len(data) // len(modes))
    parts = [data[i * step : (i + 1) * step] for i in range(len(modes))]
    blocks = [blte_block(mode, part) for mode, part in zip(modes, parts)]
    table = b"".join(struct.pack(">II", len(b), len(p)) + md5(b) for b, p in zip(blocks, parts))
    head_size = 8 + 4 + len(table)
    return b"BLTE" + struct.pack(">I", head_size) + b"\x0f" + len(blocks).to_bytes(3, "big") + table + b"".join(blocks)


def encoding_file(ce, page_kb=1):
    """Encoding file over {ckey: (ekey, size)}, plus filler entries so lookups cross page boundaries."""
    ce = dict(ce)
    for n in range(60):
        ce.setdefault(md5(b"filler %d" % n), (md5(b"filler ekey %d" % n), n))
    page_size = page_kb * 1024
    entries = [b"\x01" + size.to_bytes(5, "big") + ckey + ekey for ckey, (ekey, size) in sorted(ce.items())]
    per_page = page_size // len(entries[0])
    pages = [entries[i : i + per_page] for i in range(0, len(entries), per_page)]
    blobs = [b"".join(page).ljust(page_size, b"\0") for page in pages]
    table = b"".join(page[0][6:22] + md5(blob) for page, blob in zip(pages, blobs))
    espec = b"z\0"
    head = b"EN" + bytes([1, 16, 16]) + struct.pack(">HHIIBI", page_kb, page_kb, len(pages), 0, 0, len(espec))
    return head + espec + table + b"".join(blobs)


def root_file(blocks, version=1):
    """MFST root over [(locale_flags, content_flags, [(fileID, ckey), ...])]; version 0 = 8.2 header, 1/2 = 10.1.7+."""
    total = sum(len(records) for _, _, records in blocks)
    named = sum(len(records) for _, content, records in blocks if not content & NO_NAME_HASH)
    if version == 0:
        out = b"TSFM" + struct.pack("<II", total, named)
    else:
        out = b"TSFM" + struct.pack("<IIIII", 24, version, total, named, 0)
    for locale, content, records in blocks:
        if version == 2:
            out += struct.pack("<IIIIB", len(records), locale, content, 0, 0)
        else:
            out += struct.pack("<III", len(records), content, locale)
        previous = -1
        for file_id, _ in records:
            out += struct.pack("<i", file_id - previous - 1)
            previous = file_id
        out += b"".join(ckey for _, ckey in records)
        if not (total != named and content & NO_NAME_HASH):
            out += b"\0" * 8 * len(records)
    return out


def bucket_of(key):
    x = 0
    for byte in key[:9]:
        x ^= byte
    return (x & 0xF) ^ (x >> 4)


def index_file(bucket, entries):
    head = struct.pack("<HBBBBBBQ", 7, bucket, 0, 4, 5, 9, 30, 0x4000000000)
    body = b"".join(
        key + ((archive << 30) | offset).to_bytes(5, "big") + struct.pack("<I", size)
        for key, archive, offset, size in sorted(entries)
    )
    return struct.pack("<II", 16, 0) + head + b"\0" * 8 + struct.pack("<II", len(body), 0) + body


def ekey_of(blte_bytes):
    """TACT EKey: MD5 of the BLTE header and chunk table, or of the whole stream when headerSize is 0."""
    head_size = struct.unpack_from(">I", blte_bytes, 4)[0]
    return md5(blte_bytes[: head_size or len(blte_bytes)])


def write_install(install, products, root_version=1, stale_index=False, zero_headers=False):
    """A local CASC store under `install` shared by {product: [(locale, content, {fileID: (data, modes)}), ...]}.

    `modes` is a blte() mode string, or "-" for one headerless N block. `stale_index` adds an older .idx per bucket
    whose entries point at a missing archive, so a reader that picks the wrong version fails. `zero_headers` blanks
    every 30-byte record header."""
    data_dir = install / "Data" / "data"
    data_dir.mkdir(parents=True)
    archive = bytearray()
    entries = []

    def store(blte_bytes):
        ekey = ekey_of(blte_bytes)
        record = ekey[::-1] + struct.pack("<I", 30 + len(blte_bytes)) + b"\0" * 10 + blte_bytes
        entries.append((ekey[:9], 0, len(archive), len(record)))
        if zero_headers:  # as 12.1.5 writes some records: blank header, plus an entry for the BLTE behind it
            record = bytes(30) + blte_bytes
            entries.append((ekey[:9], 0, len(archive) + 30, len(blte_bytes)))
        archive.extend(record)
        return ekey

    rows = ["Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|Version!STRING:0|Product!STRING:0"]
    for number, (product, blocks) in enumerate(products.items()):
        ce = {}

        def put(data, modes):
            ckey = md5(data)
            encoded = blte(data, "N", headerless=True) if modes == "-" else blte(data, modes)
            ce[ckey] = (store(encoded), len(data))
            return ckey

        records = [(loc, content, [(fid, put(*files[fid])) for fid in sorted(files)]) for loc, content, files in blocks]
        root_ckey = put(root_file(records, root_version), "ZZ")
        encoding = encoding_file(ce)
        config = f"# Build Configuration\n\nroot = {root_ckey.hex()}\n"
        config += f"encoding = {md5(encoding).hex()} {store(blte(encoding, 'Z')).hex()}\n"
        build_key = md5(config.encode()).hex()
        path = install / "Data" / "config" / build_key[:2] / build_key[2:4] / build_key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(config)
        rows.append(f"eu|1|{build_key}|1.0.{number}.{100 + number}|{product}")
    (install / ".build.info").write_text("\n".join(rows) + "\n")
    (data_dir / "data.000").write_bytes(bytes(archive))
    for bucket in range(16):
        mine = [entry for entry in entries if bucket_of(entry[0]) == bucket]
        (data_dir / f"{bucket:02x}00000002.idx").write_bytes(index_file(bucket, mine))
        if stale_index:
            wrong = [(key, 7, 0, size) for key, _, _, size in mine]
            (data_dir / f"{bucket:02x}00000001.idx").write_bytes(index_file(bucket, wrong))
    return install
