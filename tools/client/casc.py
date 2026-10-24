"""Read-only, stdlib-only reader for the installed client's local CASC store (Ruling R3).

    open_store(install, product) -> CascStore: read(file_id) -> bytes | None, file_ids(), close(), last_note

Chain (wowdev.wiki/TACT, /CASC, /BLTE): `.build.info` row for the product -> build config under Data/config ->
encoding file (CKey -> EKey) and root file (fileDataID -> CKey) -> Data/data/*.idx (EKey -> archive, offset) ->
data.### -> BLTE. Local only: a file that is not on disk, or wholly encrypted, reads as None; a file with some
encrypted blocks reads with those blocks zero-filled. Either way `last_note` says so.

Root choice (as TACTSharp RootInstance.cs): a block counts when its locale flags include enUS (blocks for every
locale set that bit too) and its content flags lack LowViolence; when several counted blocks hold one fileDataID,
the first wins, except that HighResTexture blocks rank after all others (unlike TACTSharp): wowf 1.60 lists them
first, and their files are the optional high-res download, absent from this install for 399 of 400 sampled.
"""

import bisect
import struct
from pathlib import Path

from tools.client import casc_blte
from tools.client.casc_index import LocalStorage

HIGH_RES = 0x1
ENUS = 0x2
LOW_VIOLENCE = 0x80
NO_NAME_HASH = 0x10000000


class CascError(Exception):
    """The store cannot be opened: missing product, config or a table this reader does not understand."""


def build_info_rows(text):
    """`.build.info` rows as dicts keyed by header name without its `!TYPE:n` suffix."""
    lines = [line for line in text.splitlines() if line.strip()]
    header = [name.split("!")[0] for name in lines[0].split("|")] if lines else []
    return [dict(zip(header, line.split("|"))) for line in lines[1:]]


def build_row(install, product):
    rows = [row for row in build_info_rows((install / ".build.info").read_text()) if row.get("Product") == product]
    if not rows:
        raise CascError(f"product {product!r} is not in {install / '.build.info'}")
    return next((row for row in rows if row.get("Active") == "1"), rows[0])


def read_config(data, key):
    """{name: [values]} of a `name = v1 v2` config file stored at Data/config/<k[0:2]>/<k[2:4]>/<k>."""
    path = data / "config" / key[:2] / key[2:4] / key
    if not path.is_file():
        raise CascError(f"build config {key} not found under {data / 'config'}")
    config = {}
    for line in path.read_text().splitlines():
        name, sep, value = line.partition(" = ")
        if sep and not name.startswith("#"):
            config[name.strip()] = value.split()
    return config


class Encoding:
    """CKey -> EKeys over the encoding file's CEKey pages; pages are parsed on first use and kept."""

    def __init__(self, data):
        if data[:2] != b"EN" or data[2] != 1 or data[3:5] != b"\x10\x10":
            raise CascError(f"unsupported encoding header {bytes(data[:5]).hex()}")
        page_kb, _, pages, _, _, espec_size = struct.unpack_from(">HHIIBI", data, 5)
        table = 22 + espec_size
        self.data = data
        self.page_size = page_kb * 1024
        self.first = [bytes(data[table + n * 32 : table + n * 32 + 16]) for n in range(pages)]
        self.pages_at = table + pages * 32
        self.pages = {}

    def page(self, n):
        entries = self.pages.get(n)
        if entries is None:
            entries = {}
            data, pos = self.data, self.pages_at + n * self.page_size
            end = pos + self.page_size
            while pos + 22 <= end and data[pos]:
                count = data[pos]
                ckey = bytes(data[pos + 6 : pos + 22])
                entries[ckey] = [bytes(data[pos + 22 + 16 * k : pos + 38 + 16 * k]) for k in range(count)]
                pos += 22 + 16 * count
            self.pages[n] = entries
        return entries

    def ekeys(self, ckey):
        n = bisect.bisect_right(self.first, ckey) - 1
        return self.page(n).get(ckey, []) if n >= 0 else []


def root_blocks(data):
    """Yields (locale_flags, content_flags, fileDataIDs, ckey offset) for each block of an MFST root."""
    if data[:4] != b"TSFM":
        raise CascError(f"root without an MFST header is not supported: {bytes(data[:4])!r}")
    header_size, version, total, named = struct.unpack_from("<IIII", data, 4)
    if version in (1, 2):  # 10.1.7+: magic, header_size, version, total, named, padding (TACTSharp tests the same)
        pos = header_size
    else:  # 8.2 to 10.1.5: magic, total, named
        version, total, named, pos = 1, header_size, version, 12
    hashes_optional = total != named
    while pos < len(data):
        if version == 2:
            count, locale, unk1, unk2, unk3 = struct.unpack_from("<IIIIB", data, pos)
            content, pos = unk1 | unk2 | (unk3 << 17), pos + 17
        else:
            count, content, locale = struct.unpack_from("<III", data, pos)
            pos += 12
        ids, previous = [], -1
        for delta in struct.unpack_from(f"<{count}i", data, pos):
            previous += 1 + delta
            ids.append(previous)
        ckeys = pos + 4 * count
        pos = ckeys + 16 * count
        if not (hashes_optional and content & NO_NAME_HASH):
            pos += 8 * count
        yield locale, content, ids, ckeys


def root_index(data):
    """{fileDataID: offset of its CKey in `data`} under the root choice in the module docstring."""
    counted = [block for block in root_blocks(data) if block[0] & ENUS and not block[1] & LOW_VIOLENCE]
    chosen = {}
    for _, _, ids, ckeys in reversed(sorted(counted, key=lambda block: block[1] & HIGH_RES)):
        chosen.update(zip(ids, range(ckeys, ckeys + 16 * len(ids), 16)))
    return chosen


class CascStore:
    def __init__(self, install, product):
        data = install / "Data"
        config = read_config(data, build_row(install, product)["Build Key"])
        self.storage = LocalStorage(data / "data")
        self.last_note = None
        try:
            encoding_ekey = bytes.fromhex(config["encoding"][1])
            self.encoding = Encoding(self.decode(encoding_ekey, "encoding file"))
            root_ckey = bytes.fromhex(config["root"][0])
            self.root = self.decode(self.ekey(root_ckey, "root file"), "root file")
            self.ckeys = root_index(self.root)
        except Exception:
            self.storage.close()
            raise

    def ekey(self, ckey, what):
        ekeys = self.encoding.ekeys(ckey)
        if not ekeys:
            raise CascError(f"{what} ckey {ckey.hex()} not in the encoding file")
        return ekeys[0]

    def decode(self, ekey, what):
        blte = self.storage.read(ekey)
        if blte is None:
            raise CascError(f"{what} ekey {ekey.hex()} not in the local indices")
        return casc_blte.decode(blte)

    def read(self, file_id):
        """The file's bytes, or None; `last_note` says why it is None or which blocks were zero-filled."""
        self.last_note = None
        at = self.ckeys.get(file_id)
        if at is None:
            self.last_note = f"id {file_id} not in root"
            return None
        ckey = bytes(self.root[at : at + 16])
        for ekey in self.encoding.ekeys(ckey):
            blte = self.storage.read(ekey)
            if blte is None:
                continue
            holes = []
            try:
                data = casc_blte.decode(blte, holes)
            except casc_blte.Unreadable as err:
                self.last_note = f"id {file_id}: {err}"
                return None
            if holes:
                self.last_note = f"id {file_id}: {len(holes)} encrypted block(s) zero-filled: " + "; ".join(holes)
            return data
        self.last_note = f"id {file_id} (ckey {ckey.hex()}) not in the local store"
        return None

    def file_ids(self):
        return self.ckeys.keys()

    def close(self):
        self.storage.close()


def open_store(install, product):
    return CascStore(Path(install), product)
