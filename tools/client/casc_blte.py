"""BLTE decoding (wowdev.wiki/BLTE): plain (N) and zlib (Z) blocks; encrypted (E, no keys), LZ4 (4) and nested (F)
blocks are unreadable, except that decode() can zero-fill encrypted blocks of a partly readable stream."""

import struct
import zlib

ENTRY_SIZES = {0x0F: 24, 0x10: 40}


class BlteError(Exception):
    """The bytes are not well-formed BLTE."""


class Unreadable(Exception):
    """Well-formed BLTE this reader cannot decode; str() says why."""


class Encrypted(Unreadable):
    """An E block (this reader holds no keys); `key` is its key name."""

    def __init__(self, key):
        super().__init__(f"encrypted block (key {key})")
        self.key = key


def block(data):
    mode = bytes(data[:1])
    if mode == b"N":
        return bytes(data[1:])
    if mode == b"Z":
        return zlib.decompress(data[1:])
    if mode == b"E":
        # little-endian u64, as TACTSharp reads it and as DB2 section headers store tact_key_hash
        raise Encrypted(f"{int.from_bytes(data[2 : 2 + data[1]], 'little'):016x}" if len(data) > 1 else "?")
    if mode == b"4":
        raise Unreadable("lz4 block (no stdlib decoder)")
    if mode == b"F":
        raise Unreadable("nested BLTE (F) block")
    raise BlteError(f"unknown block mode {mode!r}")


def decode(data, holes=None):
    """The decoded bytes of a BLTE stream; any encrypted block raises Unreadable naming how many and their keys.

    With a `holes` list, each encrypted block of a chunked stream decodes as zeros of its table size and its key
    name is appended (TACTSharp BLTE.cs does the same for unknown keys; DB2 readers skip the sections it covers).
    A stream whose every block is encrypted still raises.
    """
    data = memoryview(data)  # blocks are sliced without copying; the encoding file is ~190 MB
    if data[:4] != b"BLTE" or len(data) < 8:
        raise BlteError(f"no BLTE magic: {bytes(data[:4])!r}")
    head_size = struct.unpack_from(">I", data, 4)[0]
    if head_size == 0:
        spans = [(data[8:], None)]
    else:
        entry_size = ENTRY_SIZES.get(data[8])
        count = int.from_bytes(data[9:12], "big")
        if entry_size is None or count == 0 or head_size != 12 + count * entry_size:
            raise BlteError(f"bad chunk table: format {data[8]:#x}, {count} blocks, header {head_size} bytes")
        spans, pos = [], head_size
        for n in range(count):
            raw_size, logical_size = struct.unpack_from(">II", data, 12 + n * entry_size)
            spans.append((data[pos : pos + raw_size], logical_size))
            pos += raw_size
    out, keys = [], []
    for n, (raw, logical_size) in enumerate(spans):
        try:
            part = block(raw)
        except Encrypted as err:
            keys.append(err.key)
            part = bytes(logical_size or 0)
        if logical_size is not None and len(part) != logical_size:
            raise BlteError(f"block {n}: {len(part)} bytes, table says {logical_size}")
        out.append(part)
    if keys and (holes is None or len(keys) == len(spans)):
        raise Unreadable(f"{len(keys)} of {len(spans)} blocks encrypted (keys {', '.join(keys)})")
    if keys:
        holes.extend(keys)
    return b"".join(out)
