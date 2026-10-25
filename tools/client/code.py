"""Interface code writer: Blizzard's Lua, XML, TOC and XSD text files, as <out>/code/<path under interface/>."""

from tools.client import paths

PREFIXES = ("interface/addons/blizzard_", "interface/framexml/")
SUFFIXES = (".lua", ".xml", ".toc", ".xsd")


def wanted(path):
    low = path.replace("\\", "/").lower()
    return low.startswith(PREFIXES) and low.endswith(SUFFIXES)


def write(source, out, ctx):
    """Writes every wanted file the source can read; returns how many. Unsafe or unreadable paths go to ctx.notes."""
    written = 0
    for path in source.paths():
        if not wanted(path):
            continue
        rel = paths.safe_rel(path)
        if rel is None:
            ctx.notes.append(f"code: skipped unsafe path {path!r}")
            continue
        data = source.read(path)
        if data is None:
            ctx.notes.append(f"code: could not read {path}")
            continue
        target = out / "code" / rel[len("interface/") :]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        written += 1
    return written
