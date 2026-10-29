"""DB2 tables to <out>/db2/<lowername>.lua (`return { [id] = { Field = value } }`) and the atlas table to atlas.lua.
The spell and item tables (R5) are too big for one Lua 5.1 chunk, so they keep a column whitelist and are written as
db2/<lowername>/<id // 10000>.lua. The window tables (WINDOW_TABLES) keep a whitelist too, and each `index` column also
gets a lookup file db2/index/<lowername>.<column lowercased>.lua = `return { [value] = { rowID, ... } }`."""

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
        "Display_lang", "OverallQualityID", "ItemLevel", "RequiredLevel", "InventoryType", "Description_lang", "Stackable",
    ),  # fmt: skip
}
R5_TABLES = tuple(R5_COLUMNS)
R5_KEYS = {"SpellMisc": "SpellID"}  # every other R5 table is keyed by its row ID
CHUNK = 10000


def window(columns, index="", chunked=False):
    return {"columns": tuple(columns.split()), "index": tuple(index.split()), "chunked": chunked}


# Tasks 12.3-12.7 read these through BlizzardData (blizzard_data.lua). Every table is keyed by row ID and whitelists its
# columns (an `index` column is also a lookup file); B17 in docs/client-sources.md names the columns each layout has.
WINDOW_TABLES = {
    "TalentTab": window("ID Name_lang Description_lang ClassMask OrderIndex BackgroundFile"),
    "Talent": window("ID TabID TierID ColumnIndex SpellRank PrereqTalent PrereqRank", index="TabID"),
    "TraitNode": window("ID TraitTreeID PosX PosY Type Flags", index="TraitTreeID"),
    "TraitNodeXTraitNodeEntry": window("ID TraitNodeID TraitNodeEntryID Index", index="TraitNodeID"),
    "TraitNodeEntry": window("ID TraitDefinitionID NodeEntryType MaxRanks"),
    "TraitDefinition": window("ID SpellID OverrideName_lang OverrideIcon"),
    "TraitEdge": window("ID LeftTraitNodeID RightTraitNodeID Type VisualStyle", index="LeftTraitNodeID"),
    "UiMap": window("ID Name_lang Type ParentUiMapID Flags"),
    "UiMapXMapArt": window("ID UiMapID UiMapArtID PhaseID", index="UiMapID"),
    "UiMapArt": window("ID UiMapArtStyleID"),
    "UiMapArtStyleLayer": window(
        "ID UiMapArtStyleID LayerIndex LayerWidth LayerHeight TileWidth TileHeight MinScale MaxScale AdditionalZoomSteps",
        index="UiMapArtStyleID",
    ),
    "UiMapArtTile": window("ID UiMapArtID LayerIndex RowIndex ColIndex FileDataID", index="UiMapArtID", chunked=True),
    "WorldMapOverlay": window(
        "ID UiMapArtID TextureWidth TextureHeight OffsetX OffsetY HitRectTop HitRectBottom HitRectLeft HitRectRight Flags",
        index="UiMapArtID",
    ),
    "WorldMapOverlayTile": window(
        "ID WorldMapOverlayID LayerIndex RowIndex ColIndex FileDataID", index="WorldMapOverlayID", chunked=True
    ),
    "ItemModifiedAppearance": window("ID ItemID ItemAppearanceModifierID ItemAppearanceID", index="ItemID", chunked=True),
    "ItemAppearance": window("ID DefaultIconFileDataID", chunked=True),
    "ItemClass": window("ID ClassName_lang ClassID"),
    "ItemSubClass": window("ID DisplayName_lang VerboseName_lang ClassID SubClassID"),
}


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
    """`return { [id] = { Field = value, ... } }` for (id, row) pairs with int ids (see int_keyed), ids ascending."""
    lines = ["return {"]
    for key, row in sorted(entries, key=lambda entry: entry[0]):
        cells = []
        for field, value in row.items():
            name = field if IDENT.match(field) and field not in KEYWORDS else f"[{lua_string(field)}]"
            cells.append(f"{name} = {lua_scalar(value)}")
        lines.append(f"\t[{int(key)}] = {{ {', '.join(cells)} }},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def int_keyed(name, entries, ctx):
    """The (key, row) pairs whose key is an int. A DBD that types the key column as a string would otherwise put
    its text into the generated Lua; such rows are counted in ctx.notes."""
    kept = [entry for entry in entries if type(entry[0]) is int]  # not bool, which would print as True
    if len(kept) < len(entries):
        ctx.notes.append(f"db2: {name}: {len(entries) - len(kept)} rows without an integer key were skipped")
    return kept


def to_lua(rows, name, ctx):
    """The table of rows keyed by their ID; a row without an ID or with a non-int one is left out."""
    return lua_rows(int_keyed(name, [(row["ID"], row) for row in rows if "ID" in row], ctx))


def r5_entries(name, rows, ctx, columns=None):
    """[(key, {column: value})] of an R5 table (or of a window table, with its `columns`): the whitelisted columns only
    (a name the DBD lacks is noted and skipped), keyed by R5_KEYS. A repeated key keeps the lowest row ID and is
    counted in ctx.notes."""
    wanted = columns or R5_COLUMNS[name]
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
    return int_keyed(name, entries, ctx)


def lua_lists(entries):
    """`return { [value] = { rowID, ... } }` for (value, row IDs) pairs, values ascending."""
    lines = ["return {"]
    for value, ids in sorted(entries, key=lambda entry: entry[0]):
        lines.append(f"\t[{int(value)}] = {lua_scalar(ids)},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write_keyed(base, stem, entries, chunked, render):
    """base/<stem>.lua, or with `chunked` base/<stem>/<key // CHUNK>.lua per key range that holds an entry, rendered
    by render(entries); returns the files written. An older export of the other form goes first."""
    (base / f"{stem}.lua").unlink(missing_ok=True)
    shutil.rmtree(base / stem, ignore_errors=True)
    if not chunked:
        base.mkdir(parents=True, exist_ok=True)
        write_atomic(base / f"{stem}.lua", render(entries))
        return 1
    groups = {}
    for entry in entries:
        groups.setdefault(entry[0] // CHUNK, []).append(entry)
    for number, group in groups.items():
        target = base / stem / f"{number}.lua"
        target.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(target, render(group))
    return len(groups)


def write_chunks(out, name, entries):
    """db2/<lowername>/<id // CHUNK>.lua per id range that holds a row; returns the files written. An older
    single-file or chunked export of the table goes first."""
    return write_keyed(Path(out) / "db2", name.lower(), entries, True, lua_rows)


def index_entries(name, column, entries, ctx):
    """[(value, [rowID, ...])] of an index column over the table's (rowID, row) entries, row IDs ascending; a row
    whose value is not an int is counted in ctx.notes. None when the table kept no such column."""
    if entries and column not in entries[0][1]:
        ctx.notes.append(f"db2: {name}: index column {column} is not in the table, skipped")
        return None
    index, skipped = {}, 0
    for key, row in sorted(entries, key=lambda entry: entry[0]):
        if type(row[column]) is int:
            index.setdefault(row[column], []).append(key)
        else:
            skipped += 1
    if skipped:
        ctx.notes.append(f"db2: {name}: {skipped} rows without an integer {column} are not in its index")
    return list(index.items())


def write_window_table(out, name, spec, rows, ctx):
    """db2/<lowername>.lua (or its chunks) for a WINDOW_TABLES entry plus db2/index/<lowername>.<column>.lua per index
    column, chunked the same way; returns the files written."""
    entries = r5_entries(name, rows, ctx, spec["columns"])
    base, chunked = Path(out) / "db2", spec["chunked"]
    written = write_keyed(base, name.lower(), entries, chunked, lua_rows)
    for column in spec["index"]:
        index = index_entries(name, column, entries, ctx)
        if index is not None:
            written += write_keyed(base / "index", f"{name.lower()}.{column.lower()}", index, chunked, lua_lists)
    return written


def write(source, out, ctx):
    """Writes db2/<table>.lua for each ATLAS_TABLES entry the client holds and atlas.lua when all three are there,
    then the R5_TABLES in chunks and the WINDOW_TABLES with their indexes; returns the files written. A table the
    client or the DBDs lack is skipped."""
    written, tables = 0, {}
    for name in ATLAS_TABLES:
        rows = read_table(source, name, ctx)
        if rows is None:
            continue
        tables[name] = {row["ID"]: row for row in rows if "ID" in row}
        target = Path(out) / "db2" / f"{name.lower()}.lua"
        target.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(target, to_lua(rows, name, ctx))
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
    for name, spec in WINDOW_TABLES.items():
        rows = read_table(source, name, ctx)
        if rows is not None:
            written += write_window_table(out, name, spec, rows, ctx)
    return written
