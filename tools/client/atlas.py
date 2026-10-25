"""atlas.lua: UI texture atlas names with their sheet and tex coords, and cutting one atlas out of its sheet."""

import re
from pathlib import Path

from PIL import Image

from tools.client import art
from tools.client.manifest import lua_string, lua_value

UNSAFE = re.compile(r'[\\/:*?"<>|\x00-\x1f]')
SIDES = ("left", "right", "top", "bottom")
_loaded = {}  # atlas.lua path -> (mtime, lupa table)


def build(sheets, members, elements):
    """{lowername: entry} from {id: row} dicts of UiTextureAtlas, UiTextureAtlasMember and UiTextureAtlasElement.
    A member's name is its Element's Name (Member.UiTextureAtlasElementID -> Element.ID), else CommittedName. The
    lowest member ID wins a repeated name; a member whose sheet is unknown or empty is dropped."""
    out = {}
    for member_id in sorted(members):
        member = members[member_id]
        sheet = sheets.get(member.get("UiTextureAtlasID"))
        if not sheet or not sheet.get("AtlasWidth") or not sheet.get("AtlasHeight"):
            continue
        name = elements.get(member.get("UiTextureAtlasElementID"), {}).get("Name") or member.get("CommittedName")
        if not name or name.lower() in out:
            continue
        left, right = member["CommittedLeft"], member["CommittedRight"]
        top, bottom = member["CommittedTop"], member["CommittedBottom"]
        out[name.lower()] = {
            "name": name,
            "file": sheet["FileDataID"],
            "width": member.get("OverrideWidth") or right - left,
            "height": member.get("OverrideHeight") or bottom - top,
            "left": left / sheet["AtlasWidth"],
            "right": right / sheet["AtlasWidth"],
            "top": top / sheet["AtlasHeight"],
            "bottom": bottom / sheet["AtlasHeight"],
        }
    return out


def to_lua(entries):
    """`return { [lowername] = { name, file, width, height, left, right, top, bottom } }`, keys sorted."""
    lines = ["return {"]
    for key in sorted(entries):
        e = entries[key]
        sizes = ", ".join(f"{field} = {lua_value(e[field])}" for field in ("file", "width", "height"))
        head = f"name = {lua_string(e['name'])}, {sizes}"  # lua_value quotes a string a DBD might hand us
        sides = ", ".join(f"{side} = {e[side]!r}" for side in SIDES)
        lines.append(f"\t[{lua_string(key)}] = {{ {head}, {sides} }},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def entry_of(extract_dir, key):
    """The atlas.lua row for a lowercase name as a dict, or None."""
    from lupa import lua51

    path = Path(extract_dir) / "atlas.lua"
    try:
        stamp = path.stat().st_mtime_ns
    except OSError:
        return None
    if path not in _loaded or _loaded[path][0] != stamp:
        runtime = lua51.LuaRuntime(register_eval=False, register_builtins=False)
        _loaded[path] = (stamp, runtime.execute(path.read_text(encoding="utf-8")))
    row = _loaded[path][1][key]
    return None if row is None else dict(row.items())


def crop(extract_dir, name, *, source=None):
    """art/atlas/<lowername>.png: the atlas's pixel rect cut out of its decoded sheet. None when the name, the
    sheet or the install is missing."""
    key = name.lower()
    target = Path(extract_dir) / "art" / "atlas" / (UNSAFE.sub("_", key) + ".png")
    if target.is_file():
        return target
    entry = entry_of(extract_dir, key)
    if entry is None:
        return None
    sheet = art.art_png(extract_dir, int(entry["file"]), source=source)
    if sheet is None:
        return None
    with Image.open(sheet) as image:
        w, h = image.size
        cut = image.crop(
            (round(entry["left"] * w), round(entry["top"] * h), round(entry["right"] * w), round(entry["bottom"] * h))
        )
        art.write_png(target, art.to_png_bytes(cut))
    return target
