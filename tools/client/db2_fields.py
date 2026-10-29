"""Field decoding for WDC4/WDC5 records: bit reads, the storage kinds, and the pallet and common blocks.

Layout: wowdev.wiki/DB2 (field_storage_info). A column decodes one DBD field from one record's bytes.
"""

import struct
from typing import NamedTuple

STORAGE = struct.Struct("<HHII3I")
NONE, BITPACKED, COMMON, PALLET, PALLET_ARRAY, SIGNED = range(6)
STRING_TYPES = ("string", "locstring")


class Info(NamedTuple):
    offset: int  # bits from the record start
    size: int  # bits (the whole array for NONE; the index width for PALLET kinds)
    extra: int  # bytes this field owns in the pallet or common block
    kind: int
    a: int  # COMMON: default value; BITPACKED: bit offset in the packed area
    b: int
    c: int  # BITPACKED: flags (1 = signed); PALLET_ARRAY: elements per entry


def bits(rec, offset, width):
    """`width` bits at bit `offset` of `rec`, little-endian."""
    start, shift = offset >> 3, offset & 7
    chunk = int.from_bytes(rec[start : start + ((shift + width + 7) >> 3)], "little")
    return (chunk >> shift) & ((1 << width) - 1)


def signed(value, width):
    return value - (1 << width) if value >> (width - 1) & 1 else value


def read_infos(data, pos, count):
    if len(data) < pos + STORAGE.size * count:
        raise ValueError("DB2 field storage info runs past the end of the file")
    return [Info(*STORAGE.unpack_from(data, pos + STORAGE.size * n)) for n in range(count)]


def blocks(infos, pallet, common):
    """Per field: its pallet entries (u32 list) or common {id: value} map, sliced in field order."""
    out, at_pallet, at_common = [], 0, 0
    for info in infos:
        if info.kind in (PALLET, PALLET_ARRAY):
            chunk = pallet[at_pallet : at_pallet + info.extra]
            out.append(struct.unpack(f"<{len(chunk) // 4}I", chunk))
            at_pallet += info.extra
        elif info.kind == COMMON:
            chunk = common[at_common : at_common + info.extra]
            out.append(dict(struct.iter_unpack("<II", chunk[: len(chunk) // 8 * 8])))
            at_common += info.extra
        else:
            out.append(None)
    return out


class Column:
    def __init__(self, field, info, block):
        self.field, self.info, self.block = field, info, block
        self.count = field.length if field.is_array else 1
        if field.type in STRING_TYPES and info.kind != NONE:
            raise ValueError(f"{field.name}: a string in packed storage is not supported")

    def raw(self, rec, record_id):
        """([raw ints], bit width of each, bit offset of each) for this field in `rec`."""
        info = self.info
        if info.kind == COMMON:
            return [self.block.get(record_id, info.a)], 32, [info.offset]
        if info.kind in (PALLET, PALLET_ARRAY):
            per = info.c if info.kind == PALLET_ARRAY else 1
            index = bits(rec, info.offset, info.size)
            return list(self.block[index * per : index * per + per]), 32, [info.offset] * per
        if info.kind == NONE:
            width = info.size // self.count
            offsets = [info.offset + n * width for n in range(self.count)]
            return [bits(rec, offset, width) for offset in offsets], width, offsets
        return [bits(rec, info.offset, info.size)], info.size, [info.offset]

    def convert(self, value, width):
        field, info = self.field, self.info
        if field.type == "float":
            size, code = (8, "<d") if width == 64 else (4, "<f")
            return struct.unpack(code, (value & ((1 << 8 * size) - 1)).to_bytes(size, "little"))[0]
        by_kind = info.kind == SIGNED or (info.kind == BITPACKED and info.c & 1)
        if by_kind or (field.signed and info.kind != BITPACKED):
            return signed(value, width)
        return value

    def value(self, rec, record_id, at, strings):
        """The field's value in `rec` (a list for an array). `at` is the record's byte position in the blob of all
        sections' records; `strings(target)` reads the string at that blob position."""
        values, width, offsets = self.raw(rec, record_id)
        out = []
        for value, offset in zip(values, offsets):
            if self.field.type in STRING_TYPES:
                position = at + (offset >> 3)
                out.append(strings(position + value))
            else:
                out.append(self.convert(value, width))
        return out if self.field.is_array else out[0]


def build_row(fields, cols, record_id, read, relation=0):
    """{field name: value} in DBD order; `read(column)` yields each stored field. A noninline relation field takes
    `relation` (the foreign id the relationship map gives this record), any other noninline field takes the id."""
    row, stored = {}, iter(cols)
    for field in fields:
        if "noninline" in field.flags and "relation" in field.flags:
            row[field.name] = relation
        elif "noninline" in field.flags:
            if record_id is None:
                raise ValueError(f"{field.name}: no id list in the file")
            row[field.name] = record_id
        else:
            row[field.name] = read(next(stored))
    return row
