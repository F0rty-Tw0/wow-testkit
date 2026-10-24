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
    """An E block: this reader holds no keys."""


def block(data):
    mode = bytes(data[:1])
    if mode == b"N":
        return bytes(data[1:])
    if mode == b"Z":
        return zlib.decompress(data[1:])
    if mode == b"E":
        # little-endian u64, as TACTSharp reads it and as DB2 section headers store tact_key_hash
        key_name = f"{int.from_bytes(data[2 : 2 + data[1]], 'little'):016x}" if len(data) > 1 else "?"
        raise Encrypted(f"encrypted block (key {key_name})")
    if mode == b"4":
        raise Unreadable("lz4 block (no stdlib decoder)")
    if mode == b"F":
        raise Unreadable("nested BLTE (F) block")
    raise BlteError(f"unknown block mode {mode!r}")


def decode(data, holes=None):
    """The decoded bytes of a BLTE stream.

    With a `holes` list, each encrypted block of a chunked stream decodes as zeros of its table size and a reason
    is appended (TACTSharp BLTE.cs does the same for unknown keys; DB2 readers skip the sections it covers). A
    stream whose every block is encrypted still raises Unreadable.
    """
    data = memoryview(data)  # blocks are sliced without copying; the encoding file is ~190 MB
    if data[:4] != b"BLTE" or len(data) < 8:
        raise BlteError(f"no BLTE magic: {bytes(data[:4])!r}")
    head_size = struct.unpack_from(">I", data, 4)[0]
    if head_size == 0:
        return block(data[8:])
    entry_size = ENTRY_SIZES.get(data[8])
    count = int.from_bytes(data[9:12], "big")
    if entry_size is None or count == 0 or head_size != 12 + count * entry_size:
        raise BlteError(f"bad chunk table: format {data[8]:#x}, {count} blocks, header {head_size} bytes")
    out = []
    pos = head_size
    zeroed = 0
    for n in range(count):
        raw_size, logical_size = struct.unpack_from(">II", data, 12 + n * entry_size)
        try:
            part = block(data[pos : pos + raw_size])
        except Encrypted as err:
            if holes is None or zeroed + 1 == count:
                raise
            part = bytes(logical_size)
            holes.append(f"block {n} {err}, {logical_size} bytes zero-filled")
            zeroed += 1
        if len(part) != logical_size:
            raise BlteError(f"block {n}: {len(part)} bytes, table says {logical_size}")
        out.append(part)
        pos += raw_size
    return b"".join(out)
