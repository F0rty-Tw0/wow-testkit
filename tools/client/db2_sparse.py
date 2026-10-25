"""Offset-map (sparse) records of a WDC4/WDC5 section: each record sits at its own offset and size, fields follow one
another with no padding, and a string is stored in place, NUL-terminated. Only unpacked fields occur in such tables."""

import struct

from tools.client import db2_fields

ENTRY = struct.Struct("<IH")


def read_field(rec, column, at):
    """(value, bit position after it) of `column` read from bit `at` of the record `rec`."""
    info, field = column.info, column.field
    if info.kind != db2_fields.NONE:
        raise ValueError(f"{field.name}: packed storage in an offset-map table is not supported")
    out = []
    for _ in range(column.count):
        if field.type in db2_fields.STRING_TYPES:
            end = rec.find(b"\0", at >> 3)
            if end < 0:
                raise ValueError("unterminated string")
            out.append(rec[at >> 3 : end].decode("utf-8", "replace"))
            at = (end + 1) * 8
        else:
            width = info.size // column.count
            out.append(column.convert(db2_fields.bits(rec, at, width), width))
            at += width
    return (out if field.is_array else out[0]), at


def rows(data, section, map_at, ids, fields, cols):
    """(id, row) for each map entry of `section`; `map_at` is where its offset map starts, `ids` the id list (empty
    when the id is an inline field)."""
    count = section.offset_map_ids
    if map_at + ENTRY.size * count > len(data):
        raise ValueError("DB2 offset map runs past the end of the file")
    id_field = next((f for f in fields if "id" in f.flags), None)
    for number in range(count):
        offset, size = ENTRY.unpack_from(data, map_at + ENTRY.size * number)
        rec, at = bytes(data[offset : offset + size]), [0]

        def read(column):
            value, at[0] = read_field(rec, column, at[0])
            return value

        record_id = ids[number] if ids else None
        row = db2_fields.build_row(fields, cols, record_id, read)
        yield (row[id_field.name] if record_id is None and id_field is not None else record_id), row
