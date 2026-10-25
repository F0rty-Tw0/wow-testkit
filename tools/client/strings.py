"""GlobalStrings: runs Blizzard's globalstrings.lua in a bare Lua 5.1 and writes the string globals per locale."""

import re

from tools.client import db2_export, paths
from tools.client.manifest import IDENT, KEYWORDS

LOCALE_NAMES = "enUS deDE esES esMX frFR itIT koKR ptBR ruRU zhCN zhTW"
LOCALES = {name.lower(): name for name in LOCALE_NAMES.split()}
RUNNER = (
    "function(text) local chunk, err = loadstring(text, '=globalstrings'); if not chunk then error(err, 0) end; "
    "local env = {}; setfenv(chunk, env); chunk(); return env end"
)
MAX_MEMORY = 256 * 1024 * 1024  # GlobalStrings is a few MB; the cap only stops a runaway chunk
BYTE_ESCAPE =r"\\(?:\d{1,2}(?!\d)|[01]\d\d|2[0-4]\d|25[0-5])"  # Lua 5.1 \ddd: up to 3 digits, greedy, at most 255
LUA_ESCAPE = re.compile(rf"((?:{BYTE_ESCAPE})+)|\\([abfnrtv\\\"'])")
LUA_CHARS = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v"}
ESCAPES = {'"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r"}


class StringsError(Exception):
    """The chunk would not load or run, is bytecode, or a value is not UTF-8."""


def parse_global_strings(text):
    """The string-valued globals `text` sets. The chunk runs under an empty environment, so it has no os, io or
    require; anything it needs beyond plain assignments raises StringsError. So do precompiled bytecode, which
    loadstring would run unchecked, and a chunk that allocates more than MAX_MEMORY."""
    from lupa import lua51

    data = text.encode("utf-8") if isinstance(text, str) else text
    if data[:1] == b"\x1b":  # Lua 5.1's loadstring takes a binary chunk when the first byte is ESC
        raise StringsError("the chunk is precompiled bytecode, which is never run")
    lua = lua51.LuaRuntime(encoding=None, register_eval=False, register_builtins=False, max_memory=MAX_MEMORY)
    run = lua.eval(RUNNER)
    try:
        env = run(data)
    except lua51.LuaMemoryError as exc:
        raise StringsError(f"the chunk needs more than {MAX_MEMORY >> 20} MB of memory") from exc
    except lua51.LuaError as exc:
        raise StringsError(str(exc)) from exc
    result = {}
    for key, value in env.items():
        if isinstance(key, bytes) and isinstance(value, bytes):
            try:
                result[key.decode("utf-8")] = value.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise StringsError(f"{key!r} is not UTF-8") from exc
    return result


def unescape(text):
    """DB2 TagText with its Lua escapes decoded. Retail 70575 mixes forms: `Abandon \\"%s\\"?` and `says:\\32` are
    escaped, `Message of the Day: "%s"` and KEY_BACKSLASH `\\` are not. So only Lua 5.1's escapes (\\n, \\", \\\\,
    \\ddd and the rest) are decoded, and any other backslash stays as written. That the client reads them the same
    way is assumed: it would otherwise show a literal \\n in 382 strings. A \\ddd is a byte, as in Lua: a run of
    them is read as UTF-8 (`caf\\195\\169` is café), or one char per byte when the run is not UTF-8; a \\ddd over
    255 stays as written."""

    def decode(match):
        if match.group(1):
            data = bytes(int(code) for code in match.group(1).split("\\")[1:])
            try:
                return data.decode("utf-8")
            except UnicodeDecodeError:
                return data.decode("latin-1")
        return LUA_CHARS.get(match.group(2), match.group(2))

    return LUA_ESCAPE.sub(decode, text)


def escape(char):
    if char in ESCAPES:
        return ESCAPES[char]
    return "\\%03d" % ord(char) if ord(char) < 32 or ord(char) == 127 else char


def to_lua(values):
    """`return { NAME = "text", ... }` with sorted keys; control characters become 3-digit decimal escapes."""
    lines = ["return {"]
    for key in sorted(values):
        lines.append(f'\t{key} = "{"".join(escape(char) for char in values[key])}",')
    lines.append("}")
    return "\n".join(lines) + "\n"


def locale_of(path, default):
    for part in path.replace("\\", "/").split("/"):
        if part.lower() in LOCALES:
            return LOCALES[part.lower()]
    return default


def from_db2(source, out, ctx):
    """Writes <out>/strings/<ctx.locales[0]>.lua from dbfilesclient/globalstrings.db2 (BaseTag -> TagText_lang);
    returns 1, or 0 when the table cannot be read. Rows lost to encrypted sections are counted in ctx.notes."""
    rows = db2_export.read_table(source, "GlobalStrings", ctx)
    if rows is None:
        return 0
    usable = [r for r in rows if IDENT.match(r["BaseTag"]) and r["BaseTag"] not in KEYWORDS]  # globals need Lua names
    values = {r["BaseTag"]: unescape(r["TagText_lang"]) for r in usable}
    if len(usable) < len(rows):
        ctx.notes.append(f"strings: {len(rows) - len(usable)} GlobalStrings tags are not Lua names and were skipped")
    target = out / "strings" / f"{ctx.locales[0]}.lua"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(to_lua(values), encoding="utf-8", newline="\n")
    return 1


def write(source, out, ctx):
    """Writes <out>/strings/<locale>.lua for every globalstrings.lua the source holds, else from the DB2
    (retail 12.x ships the strings only there); returns how many files."""
    written = 0
    for path in source.paths():
        if path.replace("\\", "/").lower().rsplit("/", 1)[-1] != "globalstrings.lua":
            continue
        if paths.safe_rel(path) is None:
            ctx.notes.append(f"strings: skipped unsafe path {path!r}")
            continue
        data = source.read(path)
        if data is None:
            ctx.notes.append(f"strings: could not read {path}")
            continue
        try:
            values = parse_global_strings(data)
        except StringsError as err:
            ctx.notes.append(f"strings: {path} did not run: {err}")
            continue
        target = out / "strings" / f"{locale_of(path, ctx.locales[0])}.lua"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(to_lua(values), encoding="utf-8", newline="\n")
        written += 1
    if written:
        return written
    if not getattr(source, "has_db2", True):  # the exportInterfaceFiles folders hold no DB2 tables
        ctx.notes.append("strings: the export holds no globalstrings.lua; GlobalStrings.db2 needs the CASC store")
        return 0
    return from_db2(source, out, ctx)
