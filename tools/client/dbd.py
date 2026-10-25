"""WoWDBDefs `.dbd` files: which fields a DB2 holds, by layout hash first, then by build.

Format: github.com/wowdev/WoWDBDefs (README). The files are data, fetched as text and cached; nothing from there runs.
"""

import os
import re
import urllib.request
from pathlib import Path
from typing import NamedTuple

from tools.client.listfile import USER_AGENT

URL = "https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/definitions/{}.dbd"
NAME = re.compile(r"^[A-Za-z0-9_]+$")
FIELD = re.compile(r"^(?:\$([^$]*)\$)?(\w+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?\s*(?://.*)?$")
COLUMN = re.compile(r"^(\w+)(?:<[^>]*>)?\s+(\w+)\??\s*(?://.*)?$")
STRING_TYPES = ("string", "locstring")


class DbdError(Exception):
    """No definition fits the file, or the text is not a `.dbd`."""


class Field(NamedTuple):
    name: str
    type: str  # int, float, string or locstring
    bits: int  # as declared; strings and floats are 32
    is_array: bool
    length: int
    flags: tuple  # the $...$ annotations: id, noninline, relation
    signed: bool = True


class Block(NamedTuple):
    layouts: list  # layout hashes, ints
    builds: list  # (low, high) version tuples
    fields: list


def version(text):
    return tuple(int(part) for part in text.strip().split("."))


def parse_builds(text):
    ranges = []
    for item in text.split(","):
        low, _, high = item.strip().partition("-")
        if low:
            ranges.append((version(low), version(high or low)))
    return ranges


def parse_field(line, types):
    match = FIELD.match(line)
    if match is None:
        raise DbdError(f"cannot read field line {line!r}")
    note, name, unsigned, bits, length = match.groups()
    kind = types.get(name, "int")
    width = int(bits) if bits else 32
    flags = tuple(part for part in (note or "").split(",") if part)
    return Field(name, kind, width, length is not None, int(length or 1), flags, not unsigned)


def parse(text):
    """The version blocks of a `.dbd`; each block's fields use the types from the COLUMNS section."""
    types, blocks, current, in_columns = {}, [], None, False
    for line in text.splitlines():
        line = line.strip()
        if not line:
            in_columns, current = False, None
        elif line == "COLUMNS":
            in_columns = True
        elif in_columns:
            match = COLUMN.match(line)
            if match:
                types[match.group(2)] = match.group(1)
        else:
            if current is None:
                current = Block([], [], [])
                blocks.append(current)
            if line.startswith("LAYOUT "):
                current.layouts.extend(int(h, 16) for h in line[7:].replace(" ", "").split(",") if h)
            elif line.startswith("BUILD "):
                current.builds.extend(parse_builds(line[6:]))
            elif not line.startswith("COMMENT "):
                current.fields.append(parse_field(line, types))
    return blocks


def pick(blocks, layout_hash, build):
    """The fields of the block that lists `layout_hash`, else the first whose BUILD ranges hold `build`."""
    for block in blocks:
        if layout_hash in block.layouts:
            return block.fields
    wanted = version(build)
    for block in blocks:
        if any(low <= wanted <= high for low, high in block.builds):
            return block.fields
    raise DbdError(f"no definition for layout {layout_hash:08X} or build {build}")


def fetch(name, cache_dir, opener=urllib.request.urlopen, refresh=False):
    """The `.dbd` text of table `name`, from <cache_dir>/<name>.dbd or downloaded to it (`refresh` downloads again)."""
    if NAME.match(name) is None:
        raise DbdError(f"bad table name {name!r}")
    cached = Path(cache_dir) / f"{name}.dbd"
    if cached.is_file() and not refresh:
        return cached.read_text(encoding="utf-8")
    request = urllib.request.Request(URL.format(name), headers={"User-Agent": USER_AGENT})
    with opener(request) as response:
        text = response.read().decode("utf-8")
    cached.parent.mkdir(parents=True, exist_ok=True)
    part = cached.with_name(cached.name + ".part")
    part.write_text(text, encoding="utf-8", newline="\n")
    os.replace(part, cached)
    return text
