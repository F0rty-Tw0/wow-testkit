"""manifest.json and manifest.lua: one table, written twice (the kit has no JSON decoder, so it reads the Lua one)."""

import json
import os
import re
from pathlib import Path

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}  # fmt: skip


def lua_string(text):
    out = []
    for char in text:
        if char in '\\"':
            out.append("\\" + char)
        elif char == "\n":
            out.append("\\n")
        elif ord(char) < 32 or ord(char) == 127:
            out.append("\\%03d" % ord(char))
        else:
            out.append(char)
    return '"' + "".join(out) + '"'


def lua_value(value, depth=0):
    """Lua source for a JSON-like value; dict keys are sorted, lists become arrays."""
    pad, inner = "  " * depth, "  " * (depth + 1)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, (list, tuple)):
        items = [inner + lua_value(item, depth + 1) + "," for item in value]
    else:
        items = []
        for key in sorted(value):
            name = key if IDENT.match(key) and key not in KEYWORDS else "[" + lua_string(key) + "]"
            items.append(f"{inner}{name} = {lua_value(value[key], depth + 1)},")
    return "{\n" + "\n".join(items) + "\n" + pad + "}" if items else "{}"


def write_atomic(path, text):
    part = path.with_name(path.name + ".part")
    part.write_text(text, encoding="utf-8", newline="\n")
    os.replace(part, path)


def write(directory, data):
    """Writes manifest.json (indent 1, keys sorted) and manifest.lua into `directory`, creating it."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    write_atomic(directory / "manifest.json", json.dumps(data, indent=1, sort_keys=True) + "\n")
    write_atomic(directory / "manifest.lua", "return " + lua_value(data) + "\n")


def read(directory):
    """The manifest in `directory`; {} when there is none or it cannot be read (the next run rewrites it)."""
    try:
        return json.loads((Path(directory) / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def builds(home, flavor):
    """Build numbers that have an extract (a folder with a manifest.json) under <home>/client/<flavor>."""
    root = Path(home) / "client" / flavor
    found = [d.name for d in root.iterdir() if (d / "manifest.json").is_file()] if root.is_dir() else []
    return sorted(found, key=lambda name: (not name.isdigit(), int(name) if name.isdigit() else 0, name))


def stale(home, flavor, current_build):
    """Extract builds of the flavor other than `current_build`, oldest first."""
    return [name for name in builds(home, flavor) if name != current_build]
