"""Local CASC storage (wowdev.wiki/CASC): Data/data/*.idx bucket indices and the data.### archives they point into."""

import bisect
import hashlib
import struct

ENTRIES_AT = 0x28
KEY = 9
ENTRY = 18
RECORD_HEADER = 30


def hashes_to(blte, ekey):
    """TACT: the EKey is the MD5 of the BLTE header and chunk table, or of the whole stream when headerSize is 0."""
    if len(blte) < 8 or blte[:4] != b"BLTE":
        return False
    head_size = struct.unpack_from(">I", blte, 4)[0]
    return hashlib.md5(blte[: head_size or len(blte)]).digest() == bytes(ekey)


class CascIndexError(Exception):
    """An .idx file this reader does not understand."""


class Keys:
    """The 9-byte keys of a sorted .idx entry blob, as a sequence bisect can search without copying them out."""

    def __init__(self, blob):
        self.blob = blob

    def __len__(self):
        return len(self.blob) // ENTRY

    def __getitem__(self, i):
        return self.blob[i * ENTRY : i * ENTRY + KEY]


def bucket_of(ekey):
    x = 0
    for byte in ekey[:KEY]:
        x ^= byte
    return (x & 0xF) ^ (x >> 4)


def latest_indices(data_dir):
    """{bucket: path} of the highest version .idx per bucket (name = 2 hex digits bucket + 8 hex digits version)."""
    best = {}
    for path in data_dir.glob("*.idx"):
        stem = path.stem
        if len(stem) != 10:
            continue
        try:
            bucket, version = int(stem[:2], 16), int(stem[2:], 16)
        except ValueError:
            continue
        if bucket < 16 and (bucket not in best or version > best[bucket][0]):
            best[bucket] = (version, path)
    return {bucket: path for bucket, (_, path) in best.items()}


def load_index(path):
    data = path.read_bytes()
    version, _, _, size_len, offset_len, key_len, offset_bits = struct.unpack_from("<HBBBBBB", data, 8)
    if (version, size_len, offset_len, key_len, offset_bits) != (7, 4, 5, KEY, 30):
        raise CascIndexError(f"{path.name}: unsupported index layout {data[8:16].hex()}")
    size = struct.unpack_from("<I", data, 0x20)[0]
    blob = data[ENTRIES_AT : ENTRIES_AT + size]
    if len(blob) != size or size % ENTRY:
        raise CascIndexError(f"{path.name}: entries size {size} does not fit the file")
    return blob


class LocalStorage:
    """EKey -> raw BLTE bytes from the local archives. Opens every file read-only; never writes."""

    def __init__(self, data_dir):
        self.data_dir = data_dir
        self.indices = {bucket: Keys(load_index(path)) for bucket, path in latest_indices(data_dir).items()}
        self.archives = {}

    def locations(self, ekey):
        """Yields (archive, offset, size) of each index entry for this EKey, its own bucket first; a few live
        entries sit in another bucket, so the rest are searched only when the caller asks for more."""
        key = bytes(ekey[:KEY])
        home = bucket_of(key)
        for bucket in [home] + [b for b in sorted(self.indices) if b != home]:
            keys = self.indices.get(bucket)
            if keys is None:
                continue
            i = bisect.bisect_left(keys, key)
            while i < len(keys) and keys[i] == key:
                at = i * ENTRY + KEY
                packed = int.from_bytes(keys.blob[at : at + 5], "big")
                yield packed >> 30, packed & 0x3FFFFFFF, struct.unpack_from("<I", keys.blob, at + 5)[0]
                i += 1

    def archive(self, number):
        handle = self.archives.get(number)
        if handle is None:
            handle = open(self.data_dir / f"data.{number:03d}", "rb")
            self.archives[number] = handle
        return handle

    def read(self, ekey):
        """The BLTE bytes stored under `ekey` (16 bytes), or None when no local entry holds a record that is its.

        A record is its when the 30-byte header names the key and size, or else when the BLTE behind the header
        hashes to the key: 12.1.5 writes blank or unrelated headers on some records, plus a second entry that
        points straight at the BLTE, which is accepted by the same hash."""
        for number, offset, size in self.locations(ekey):
            try:
                handle = self.archive(number)
            except FileNotFoundError:
                continue
            handle.seek(offset)
            record = handle.read(size)
            if len(record) != size:
                continue
            view = memoryview(record)
            blte = view[RECORD_HEADER:]
            names_key = size >= RECORD_HEADER and record[:16][::-1][:KEY] == bytes(ekey[:KEY])
            if names_key and struct.unpack_from("<I", record, 16)[0] == size:
                return blte
            if hashes_to(blte, ekey):
                return blte
            if hashes_to(view, ekey):
                return view
        return None

    def close(self):
        for handle in self.archives.values():
            handle.close()
        self.archives.clear()
