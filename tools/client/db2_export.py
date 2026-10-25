"""DB2 tables to <out>/db2/<lowername>.lua (`return { [id] = { Field = value } }`) and the atlas table to atlas.lua.
The spell and item tables (R5) are too big for one Lua 5.1 chunk, so they keep a column whitelist and are written as
db2/<lowername>/<id // 10000>.lua."""

import math
import shutil
from pathlib import Path

from tools.client import atlas, db2, dbd, paths
from tools.client.manifest import IDENT, KEYWORDS, lua_string, write_atomic

ATLAS_TABLES = ("UiTextureAtlas", "UiTextureAtlasMember", "UiTextureAtlasElement")
R5_COLUMNS = {
    "SpellName": ("Name_lang",),
    "Spell": ("NameSubtext_lang", "Description_lang", "AuraDescription_lang"),
    "SpellMisc": ("SpellID", "SpellIconFileDataID", "SchoolMask", "CastingTimeIndex", "DurationIndex", "RangeIndex"),
    "Item": ("ClassID", "SubclassID", "InventoryType", "IconFileDataID"),
    "ItemSparse": (
        "Display_lang", "OverallQualityID", "ItemLevel", "RequiredLevel", "InventoryType", "Description_lang",
    ),  # fmt: skip
}
R5_TABLES = tuple(R5_COLUMNS)
R5_KEYS = {"SpellMisc": "SpellID"}  # every other R5 table is keyed by its row ID
CHUNK = 10000


def dbd_dir(ctx):
    return Path(ctx.home if ctx.home is not None else paths.testkit_home()) / "dbd"


def load_fields(name, head, ctx):
    """The DBD fields for a file: the cached `.dbd` first; a stale cache gets one fresh download."""
    text = dbd.fetch(name, dbd_dir(ctx))
    try:
        return dbd.pick(dbd.parse(text), head.layout_hash, ctx.version)
    except dbd.DbdError:
        text = dbd.fetch(name, dbd_dir(ctx), refresh=True)
        return dbd.pick(dbd.parse(text), head.layout_hash, ctx.version)


def read_table(source, name, ctx):
    """The rows of table `name` as a list of dicts, or None with the reason in ctx.notes. Rows in sections this
    reader cannot decrypt are not returned; their count goes to ctx.notes."""
    path = f"dbfilesclient/{name.lower()}.db2"
    if source.file_id(path) is None:
        ctx.notes.append(f"db2: {name} has no listfile entry in this client")
        return None
    data = source.read(path, partial=True)
    if data is None:
        ctx.notes.append(f"db2: {name} could not be read")
        return None
    try:
        head = db2.header(data)
        fields = load_fields(name, head, ctx)
        rows = list(db2.read(data, fields))
    except dbd.DbdError as err:
        ctx.notes.append(f"db2: {name} has no usable definition: {err}")
        return None
    except (OSError, ValueError) as err:  # no network for the .dbd, or a layout this reader does not handle
        ctx.notes.append(f"db2: {name} not read: {err}")
        return None
    lost = db2.lost_rows(head)
    if lost:
        sections = sum(1 for s in head.sections if s.tact_key_hash)
        ctx.notes.append(f"db2: {name}: {lost} rows lost to {sections} encrypted sections")
    return rows


def lua_scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return repr(value) if math.isfinite(value) else "0"
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(lua_scalar(item) for item in value) + "}"
    return str(value)


def lua_rows(entries):
    """`return { [id] = { Field = value, ... } }` for (id, row) pairs, ids ascending."""
    lines = ["return {"]
    for key, row in sorted(entries, key=lambda entry: entry[0]):
        cells = []
        for field, value in row.items():
            name = field if IDENT.match(field) and field not in KEYWORDS else f"[{lua_string(field)}]"
            cells.append(f"{name} = {lua_scalar(value)}")
        lines.append(f"\t[{key}] = {{ {', '.join(cells)} }},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def to_lua(rows):
    """The table of rows keyed by their ID; a row without an ID is left out."""
    return lua_rows((row["ID"], row) for row in rows if "ID" in row)


def r5_entries(name, rows, ctx):
    """[(key, {column: value})] of an R5 table: the whitelisted columns only (a name the DBD lacks is noted and
    skipped), keyed by R5_KEYS. A repeated key keeps the lowest row ID and is counted in ctx.notes."""
    wanted = R5_COLUMNS[name]
    if rows:
        for column in (c for c in wanted if c not in rows[0]):
            ctx.notes.append(f"db2: {name}: column {column} is not in the DBD, skipped")
        wanted = [c for c in wanted if c in rows[0]]
    key, entries, seen = R5_KEYS.get(name, "ID"), [], set()
    keyed = sorted((r for r in rows if key in r), key=lambda r: r.get("ID", 0))
    for row in keyed:
        if row[key] not in seen:
            seen.add(row[key])
            entries.append((row[key], {column: row[column] for column in wanted}))
    if len(entries) < len(keyed):
        dropped = len(keyed) - len(entries)
        ctx.notes.append(f"db2: {name}: {dropped} rows repeat a {key} and were dropped (the lowest ID wins)")
    return entries


def write_chunks(out, name, entries):
    """db2/<lowername>/<id // CHUNK>.lua per id range that holds a row; returns the files written. An older
    single-file or chunked export of the table goes first."""
    base = Path(out) / "db2"
    (base / f"{name.lower()}.lua").unlink(missing_ok=True)
    shutil.rmtree(base / name.lower(), ignore_errors=True)
    groups = {}
    for entry in entries:
        groups.setdefault(entry[0] // CHUNK, []).append(entry)
    for number, group in groups.items():
        target = base / name.lower() / f"{number}.lua"
        target.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(target, lua_rows(group))
    return len(groups)


def write(source, out, ctx):
    """Writes db2/<table>.lua for each ATLAS_TABLES entry the client holds and atlas.lua when all three are there,
    then the R5_TABLES in chunks; returns the files written. A table the client or the DBDs lack is skipped."""
    written, tables = 0, {}
    for name in ATLAS_TABLES:
        rows = read_table(source, name, ctx)
        if rows is None:
            continue
        tables[name] = {row["ID"]: row for row in rows if "ID" in row}
        target = Path(out) / "db2" / f"{name.lower()}.lua"
        target.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(target, to_lua(rows))
        written += 1
    if len(tables) == len(ATLAS_TABLES):
        entries = atlas.build(*(tables[name] for name in ATLAS_TABLES))
        write_atomic(Path(out) / "atlas.lua", atlas.to_lua(entries))
        written += 1
    else:
        ctx.notes.append("db2: atlas.lua not written; a UiTextureAtlas table is missing")
    for name in R5_TABLES:
        rows = read_table(source, name, ctx)
        if rows is not None:
            written += write_chunks(out, name, r5_entries(name, rows, ctx))
    return written
