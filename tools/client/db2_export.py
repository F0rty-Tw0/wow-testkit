"""DB2 tables to <out>/db2/<lowername>.lua (`return { [id] = { Field = value } }`) and the atlas table to atlas.lua."""

import math
from pathlib import Path

from tools.client import atlas, db2, dbd, paths
from tools.client.manifest import IDENT, KEYWORDS, lua_string, write_atomic

ATLAS_TABLES = ("UiTextureAtlas", "UiTextureAtlasMember", "UiTextureAtlasElement")


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


def to_lua(rows):
    """`return { [id] = { Field = value, ... } }`, ids ascending; a row without an ID is left out."""
    lines = ["return {"]
    for row in sorted((r for r in rows if "ID" in r), key=lambda r: r["ID"]):
        cells = []
        for key, value in row.items():
            name = key if IDENT.match(key) and key not in KEYWORDS else f"[{lua_string(key)}]"
            cells.append(f"{name} = {lua_scalar(value)}")
        lines.append(f"\t[{row['ID']}] = {{ {', '.join(cells)} }},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write(source, out, ctx):
    """Writes db2/<table>.lua for each ATLAS_TABLES entry the client holds, then atlas.lua when all three are
    there; returns the files written."""
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
    return written
