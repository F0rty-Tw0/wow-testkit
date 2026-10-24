"""GlobalStrings: runs Blizzard's globalstrings.lua in a bare Lua 5.1 and writes the string globals per locale."""

from tools.client import paths

LOCALE_NAMES = "enUS deDE esES esMX frFR itIT koKR ptBR ruRU zhCN zhTW"
LOCALES = {name.lower(): name for name in LOCALE_NAMES.split()}
RUNNER = (
    "function(text) local chunk, err = loadstring(text, '=globalstrings'); if not chunk then error(err, 0) end; "
    "local env = {}; setfenv(chunk, env); chunk(); return env end"
)
ESCAPES = {'"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r"}


class StringsError(Exception):
    """The chunk would not load or run, or a value is not UTF-8."""


def parse_global_strings(text):
    """The string-valued globals `text` sets. The chunk runs under an empty environment, so it has no os, io or
    require; anything it needs beyond plain assignments raises StringsError."""
    from lupa import lua51

    lua = lua51.LuaRuntime(encoding=None, register_eval=False, register_builtins=False)
    run = lua.eval(RUNNER)
    try:
        env = run(text.encode("utf-8") if isinstance(text, str) else text)
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


def write(source, out, ctx):
    """Writes <out>/strings/<locale>.lua for every globalstrings.lua the source holds; returns how many."""
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
    return written
