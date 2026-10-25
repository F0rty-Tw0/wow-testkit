"""A synthetic WDC5 builder for self-tests. The tests are its oracle for the layout; the real check is the other."""

import struct

KINDS = {"none": 0, "bitpacked": 1, "common": 2, "pallet": 3, "pallet_array": 4, "signed": 5}
STRINGISH = ("string", "locstring")
HEADER = "<9I2H7I"


def elements(field, value):
    return list(value) if field.is_array else [value]


def plan_field(field, cursor, rows, compression, id_name):
    """(storage tuple, pallet bytes, common bytes, bits used in the record, pallet entries) for one stored field."""
    kind = KINDS[compression.get(field.name, "none")]
    count = field.length if field.is_array else 1
    width = 32 if field.type in STRINGISH or field.type == "float" else field.bits
    column = [tuple(elements(field, row.get(field.name, 0 if field.type not in STRINGISH else ""))) for row in rows]
    if kind in (0, 1, 5):
        return (cursor, width * count, 0, kind, 0, 0, 0), b"", b"", width * count, []
    if kind == 2:
        pairs = [(row[id_name], values[0]) for row, values in zip(rows, column) if values[0]]
        blob = b"".join(struct.pack("<II", key, value & 0xFFFFFFFF) for key, value in pairs)
        return (cursor, 0, len(blob), kind, 0, 0, 0), b"", blob, 0, []
    distinct = list(dict.fromkeys(column))
    bits = max(1, (len(distinct) - 1).bit_length())
    blob = b"".join(struct.pack("<I", value & 0xFFFFFFFF) for values in distinct for value in values)
    tail = (cursor, bits, count if kind == 4 else 0)
    return (cursor, bits, len(blob), kind, *tail), blob, b"", bits, distinct


def encode_value(field, value, position, total_records, table):
    """The raw integer a field stores. Strings go through `table` and are relative to their own position."""
    if field.type in STRINGISH:
        if value not in table["index"]:
            table["index"][value] = len(table["bytes"])
            table["bytes"] += value.encode("utf-8") + b"\0"
        return total_records + table["index"][value] - position
    if field.type == "float":
        return struct.unpack("<I", struct.pack("<f", value))[0]
    return value & ((1 << field.bits) - 1)


def sparse_record(fields, row):
    """One offset-map record: each stored field's bytes in turn, a string in place with its NUL."""
    out = b""
    for field in fields:
        if "noninline" in field.flags:
            continue
        for value in elements(field, row.get(field.name, "" if field.type in STRINGISH else 0)):
            if field.type in STRINGISH:
                out += value.encode("utf-8") + b"\0"
            else:
                out += encode_value(field, value, 0, 0, None).to_bytes(field.bits // 8, "little")
    return out


def make_sparse(fields, rows, layout_hash, copies):
    """WDC5 bytes whose records are an offset map: the id list holds the ids of a noninline ID, else the ID is a
    field of each record."""
    stored = [f for f in fields if "noninline" not in f.flags]
    id_field = next((f for f in fields if "id" in f.flags), None)
    noninline = id_field is not None and "noninline" in id_field.flags
    records = [sparse_record(fields, row) for row in rows]
    ids = b"".join(struct.pack("<I", row[id_field.name]) for row in rows) if noninline else b""
    copy_table = b"".join(struct.pack("<II", new, old) for new, old in copies)
    head_size = 4 + 4 + 128 + struct.calcsize(HEADER) + 40 + 4 * len(stored) + 24 * len(stored)
    ends = [sum(map(len, records[:n])) for n in range(len(records) + 1)]
    offset_map = b"".join(struct.pack("<IH", head_size + ends[n], len(rec)) for n, rec in enumerate(records))
    body = b"".join(records)
    ids_total = [row[id_field.name] for row in rows]
    header = struct.pack(
        HEADER,
        len(rows), len(stored), max(map(len, records), default=0), 0, 0, layout_hash,
        min(ids_total, default=0), max(ids_total, default=0), 0xFFFFFFFF,
        1 | (4 if noninline else 0), 0,
        len(stored), 0, 0, 24 * len(stored), 0, 0, 1,
    )  # fmt: skip
    section = struct.pack("<Q8I", 0, head_size, len(rows), 0, head_size + len(body), len(ids), 0, len(rows), len(copies))
    structure = b"".join(struct.pack("<hH", 0, 0) for _ in stored)
    cursor, storage = 0, b""
    for field in stored:
        bits = (32 if field.type in STRINGISH or field.type == "float" else field.bits) * (field.length if field.is_array else 1)
        storage += struct.pack("<HHII3I", cursor, bits, 0, 0, 0, 0, 0)
        cursor += bits
    prefix = b"WDC5" + struct.pack("<I", 5) + b"test".ljust(128, b"\0")
    return prefix + header + section + structure + storage + body + ids + copy_table + offset_map


def make_wdc5(fields, rows, layout_hash=0, compression=None, copies=(), locked_rows=0, sparse=False):
    """WDC5 bytes with one readable section of `rows` ({field name: value}); `compression` maps a field name to
    none, bitpacked, signed, common, pallet or pallet_array; `copies` is [(new id, copied id)];
    `locked_rows` adds a second section of zeroed rows with a non-zero tact_key_hash; `sparse` stores the rows as an
    offset map (no compression, no locked rows)."""
    if sparse:
        return make_sparse(fields, rows, layout_hash, copies)
    compression = compression or {}
    stored = [f for f in fields if "noninline" not in f.flags]
    id_field = next((f for f in fields if "id" in f.flags), None)
    noninline = id_field is not None and "noninline" in id_field.flags
    id_name = id_field.name if id_field else "ID"
    infos, entries, pallet, common, cursor = [], [], b"", b"", 0
    for field in stored:
        info, pal, com, bits, distinct = plan_field(field, cursor, rows, compression, id_name)
        infos.append(info)
        entries.append(distinct)
        pallet, common, cursor = pallet + pal, common + com, cursor + bits
    size = max(1, (cursor + 7) // 8)
    total_records = (len(rows) + locked_rows) * size
    table = {"index": {"": 0}, "bytes": bytearray(b"\0")}
    records = b""
    for number, row in enumerate(rows):
        packed = 0
        for field, info, distinct in zip(stored, infos, entries):
            offset, width, _, kind = info[:4]
            if kind == 2:
                continue
            values = elements(field, row.get(field.name, "" if field.type in STRINGISH else 0))
            if kind in (3, 4):
                values = [distinct.index(tuple(values))]
                each = width
            else:
                each = width // len(values)
            for step, value in enumerate(values):
                position = number * size + (offset + step * each) // 8
                packed |= encode_value(field, value, position, total_records, table) << (offset + step * each)
        records += packed.to_bytes(size, "little")
    strings = bytes(table["bytes"])
    ids = b"".join(struct.pack("<I", row[id_name]) for row in rows) if noninline else b""
    copy_table = b"".join(struct.pack("<II", new, old) for new, old in copies)
    locked_ids = bytes(4 * locked_rows) if noninline else b""
    sections = 2 if locked_rows else 1
    head_size = 4 + 4 + 128 + struct.calcsize(HEADER) + 40 * sections + 4 * len(stored) + 24 * len(stored)
    start = head_size + len(pallet) + len(common)
    body = records + strings + ids + copy_table
    id_index = stored.index(id_field) if id_field in stored else 0
    ids_total = [row[id_name] for row in rows]
    header = struct.pack(
        HEADER,
        len(rows) + locked_rows, len(stored), size, len(strings), 0, layout_hash,
        min(ids_total, default=0), max(ids_total, default=0), 0xFFFFFFFF,
        4 if noninline else 0, id_index,
        len(stored), 0, 0, 24 * len(stored), len(common), len(pallet), sections,
    )  # fmt: skip
    headers = struct.pack("<Q8I", 0, start, len(rows), len(strings), 0, len(ids), 0, 0, len(copies))
    if locked_rows:
        headers += struct.pack("<Q8I", 0x1234, start + len(body), locked_rows, 0, 0, len(locked_ids), 0, 0, 0)
    structure = b"".join(struct.pack("<hH", 0, 0) for _ in stored)
    storage = b"".join(struct.pack("<HHII3I", *info) for info in infos)
    prefix = b"WDC5" + struct.pack("<I", 5) + b"test".ljust(128, b"\0")
    locked = bytes(locked_rows * size) + locked_ids
    return prefix + header + headers + structure + storage + pallet + common + body + locked
