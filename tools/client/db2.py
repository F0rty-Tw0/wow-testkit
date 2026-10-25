"""WDC4 and WDC5 DB2 reader (wowdev.wiki/DB2): the header, its sections, and the rows the DBD fields name.

Not supported: offset-map (sparse) tables, which raise ValueError. Sections with a non-zero tact_key_hash hold
bytes this reader cannot decrypt (a partial read zero-fills them); they yield no rows, see `lost_rows`.
"""

import struct
from typing import NamedTuple

from tools.client import db2_fields

HEADER = struct.Struct("<9I2H7I")
SECTION = struct.Struct("<Q8I")
SPARSE = 0x1
COPY = struct.Struct("<II")


class Section(NamedTuple):
    tact_key_hash: int
    offset: int
    records: int
    strings: int
    records_end: int
    id_bytes: int
    relation_bytes: int
    offset_map_ids: int
    copies: int


class Header(NamedTuple):
    magic: bytes
    layout_hash: int
    record_count: int
    field_count: int
    record_size: int
    string_table_size: int
    table_hash: int
    min_id: int
    max_id: int
    locale: int
    flags: int
    id_index: int
    total_field_count: int
    bitpacked_offset: int
    lookup_columns: int
    storage_size: int
    common_size: int
    pallet_size: int
    sections: list
    tables_at: int  # where the field structures start


def header(data):
    magic = bytes(data[:4])
    base = {b"WDC5": 136, b"WDC4": 4}.get(magic)
    if base is None:
        raise ValueError(f"unsupported DB2 magic {magic!r}")
    if len(data) < base + HEADER.size:
        raise ValueError("truncated DB2 header")
    (records, fields, size, strings, table_hash, layout, low, high, locale, flags, id_index, total,
     packed, lookup, storage, common, pallet, count) = HEADER.unpack_from(data, base)  # fmt: skip
    pos = base + HEADER.size
    if len(data) < pos + SECTION.size * count:
        raise ValueError("truncated DB2 section headers")
    sections = [Section(*SECTION.unpack_from(data, pos + SECTION.size * n)) for n in range(count)]
    return Header(magic, layout, records, fields, size, strings, table_hash, low, high, locale, flags, id_index,
                  total, packed, lookup, storage, common, pallet, sections, pos + SECTION.size * count)  # fmt: skip


def lost_rows(head):
    """Rows (with copies) in sections this reader cannot decrypt."""
    return sum(s.records + s.copies for s in head.sections if s.tact_key_hash)


class Strings:
    """Reads a string by its position in the blob of every section's records followed by every section's strings."""

    def __init__(self, data, head):
        self.data, self.sections, self.size = data, head.sections, head.record_size
        self.records = sum(s.records for s in head.sections) * head.record_size

    def __call__(self, target):
        index = target - self.records
        if index < 0:  # an offset into the records is how an empty string is stored
            return ""
        for section in self.sections:
            if index < section.strings:
                start = section.offset + section.records * self.size + index
                end = self.data.find(b"\0", start)
                if end < 0:
                    raise ValueError("unterminated string")
                return bytes(self.data[start:end]).decode("utf-8", "replace")
            index -= section.strings
        raise ValueError("string offset past the string tables")


def columns(data, head, stored):
    infos = db2_fields.read_infos(data, head.tables_at + 4 * head.total_field_count, head.total_field_count)
    if len(infos) != len(stored):
        raise ValueError(f"the DBD names {len(stored)} stored fields, the file has {len(infos)}")
    start = head.tables_at + 4 * head.total_field_count + head.storage_size
    pallet = data[start : start + head.pallet_size]
    common = data[start + head.pallet_size : start + head.pallet_size + head.common_size]
    return [db2_fields.Column(f, i, b) for f, i, b in zip(stored, infos, db2_fields.blocks(infos, pallet, common))]


def section_rows(data, head, section, base, fields, cols, id_column, strings):
    size = head.record_size
    first = section.offset + section.records * size + section.strings
    if first + section.id_bytes + COPY.size * section.copies > len(data):
        raise ValueError("DB2 section runs past the end of the file")
    ids = struct.unpack_from(f"<{section.id_bytes // 4}I", data, first) if section.id_bytes else ()
    id_field = next((f for f in fields if "id" in f.flags), None)
    by_id = {}
    for number in range(section.records):
        rec = data[section.offset + number * size : section.offset + (number + 1) * size]
        at = base + number * size
        record_id = ids[number] if ids else None
        if record_id is None and id_column is not None:
            record_id = id_column.value(rec, None, at, strings)
        row, stored = {}, iter(cols)
        for field in fields:
            if "noninline" in field.flags:
                if record_id is None:
                    raise ValueError(f"{field.name}: no id list in the file")
                row[field.name] = record_id
            else:
                row[field.name] = next(stored).value(rec, record_id, at, strings)
        by_id[record_id] = row
        yield row
    copies = first + section.id_bytes
    for n in range(section.copies):
        new, old = COPY.unpack_from(data, copies + COPY.size * n)
        if id_field is not None and old in by_id:
            yield {**by_id[old], id_field.name: new}


def read(data, fields):
    """Rows (dicts by field name, in DBD order) of every readable section, then each section's copy-table rows."""
    head = header(data)
    if head.flags & SPARSE:
        raise ValueError("unsupported DB2: offset-map (sparse) records")
    stored = [f for f in fields if "noninline" not in f.flags]
    cols = columns(data, head, stored)
    id_column = next((c for c in cols if "id" in c.field.flags), None)
    strings, base = Strings(data, head), 0
    for section in head.sections:
        if not section.tact_key_hash:
            yield from section_rows(data, head, section, base, fields, cols, id_column, strings)
        base += section.records * head.record_size
