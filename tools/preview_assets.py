"""Asset resolution for a render snapshot: turns each assets[ref] into a file the viewer can load.

Order per asset (kind from render_assets.lua):
  path   under Interface/AddOns/<Name>/  -> addon file, else a labelled placeholder
         anything else, or a miss         -> client extract, then STANDINS, then a placeholder
  fileID / atlas                          -> client extract, then a placeholder
  font                                    -> addon file, else extract, else a stand-in with no file
Every lookup is confined to its root: parts may not hold "..", empty or drive parts, names are matched against
directory listings (never joined from the snapshot), and the real path of each hit must stay under the root.
"""

import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw

KIT_ROOT = Path(__file__).resolve().parent.parent

IMAGE_EXTS = (".png", ".jpg", ".tga", ".blp")  # probe order when a path has no extension
COPIED_EXTS = (".png", ".jpg", ".jpeg")  # everything else Pillow reads is converted to PNG
FONT_EXTS = (".ttf", ".otf")  # a font file of any other type is not copied: the viewer would serve it by that type
NO_EXTRACT_NOTE = "no client extract; art falls back to stand-ins"
DERIVED = ("source", "url", "missing", "label")


class SnapshotError(Exception):
    """A snapshot or output location the tool cannot use; the CLI exits 2."""


def _outline():
    image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle((0, 0, 15, 15), outline=(128, 128, 128, 255))
    return image


# lowercase normalised path (no extension) -> factory of a generated image
STANDINS = {
    "interface/buttons/white8x8": lambda: Image.new("RGBA", (8, 8), (255, 255, 255, 255)),
    "interface/tooltips/ui-tooltip-background": lambda: Image.new("RGBA", (8, 8), (26, 26, 26, 255)),
    "interface/tooltips/ui-tooltip-border": _outline,
}


def safe_parts(path):
    """The '/'-split parts of a texture path, or None when any part could leave a root."""
    if not isinstance(path, str):
        return None
    parts = path.replace("\\", "/").split("/")
    if any(not part.strip(" .") or ":" in part or "\0" in part for part in parts):
        return None
    return parts


def _inside(real_root, path):
    try:
        return os.path.commonpath([real_root, os.path.realpath(path)]) == real_root
    except ValueError:  # another drive
        return False


def _child(directory, part, last):
    """The listed entry of `directory` matching `part` case-insensitively (a file when `last`, else a directory)."""
    wanted = [part]
    if last and os.path.splitext(part)[1].lower() not in IMAGE_EXTS:
        wanted += [part + ext for ext in IMAGE_EXTS]
    try:
        names = os.listdir(directory)
    except OSError:
        return None
    for want in wanted:
        hits = sorted((n for n in names if n.casefold() == want.casefold()), key=lambda n: n != want)
        for name in hits:
            path = os.path.join(directory, name)
            if os.path.isfile(path) if last else os.path.isdir(path):
                return path
    return None


def find_addon_file(root, relative_parts):
    """Case-insensitive file under `root`, probing .png .jpg .tga .blp when the last part has no extension.
    None when nothing matches or a part, symlink or case-folded name would take the walk out of `root`."""
    parts = list(relative_parts)
    if not parts or safe_parts("/".join(parts)) is None or any("/" in p or "\\" in p for p in parts):
        return None
    real_root = os.path.realpath(root)
    current = real_root
    for index, part in enumerate(parts):
        current = _child(current, part, index == len(parts) - 1)
        if current is None or not _inside(real_root, current):
            return None
    return Path(current)


def _strip_image_ext(parts):
    base, ext = os.path.splitext(parts[-1])
    return parts[:-1] + [base] if ext.lower() in IMAGE_EXTS else parts


def _lazy_extract(extract_dir, asset):
    """Art the extract has not decoded yet: decoded from the client store on demand (tools.client.art/atlas).
    None when tools.client or its dependencies are missing, or the install cannot be read."""
    kind = asset.get("kind")
    try:
        if str(KIT_ROOT) not in sys.path:
            sys.path.insert(0, str(KIT_ROOT))
        from tools.client import art, atlas

        if kind == "atlas":
            return atlas.crop(extract_dir, str(asset["atlas"]))
        if kind == "fileID":
            return art.art_png(extract_dir, int(asset["fileID"]))
        parts = safe_parts(asset.get("path")) if kind == "path" else None
        return art.art_png(extract_dir, "/".join(_strip_image_ext(parts)).lower()) if parts else None
    except Exception:  # an unreadable extract or store is a miss, not a reason to abort the resolve
        return None


def lookup_extract(extract_dir, ref, asset):
    """File in the client extract for an asset, or None. Layout: <extract>/art/<path with /> and
    <extract>/art/by-id/<id>.png, PNG, as the extractor caches them (any image extension is found);
    atlases are cut from their sheet into <extract>/art/atlas/. A file not decoded yet is decoded on demand."""
    art = os.path.join(extract_dir, "art")
    kind = asset.get("kind")
    hit = None
    if kind == "fileID":
        try:
            hit = find_addon_file(art, ["by-id", "%d" % asset["fileID"]])
        except (KeyError, TypeError, ValueError, OverflowError):
            return None
    elif kind in ("path", "font"):
        parts = safe_parts(asset.get("path"))
        if parts is None:
            return None
        hit = find_addon_file(art, _strip_image_ext(parts) if kind == "path" else parts)
    if hit is None and kind in ("path", "fileID", "atlas"):
        return _lazy_extract(extract_dir, asset)
    return hit


def _addon_lookup(parts, addons):
    """(is an Interface/AddOns path, the addon file or None)."""
    if len(parts) < 3 or [p.casefold() for p in parts[:2]] != ["interface", "addons"]:
        return False, None
    root = addons.get(parts[2].casefold())
    return True, (find_addon_file(root, parts[3:]) if root else None)


def _usable(kind, hit):
    """hit, unless it is a font file of a type the viewer should not be handed."""
    return hit if hit and (kind != "font" or hit.suffix.lower() in FONT_EXTS) else None


def locate(ref, asset, addons, extract):
    """(source, file or standin factory or None) for one asset."""
    kind = asset.get("kind")
    parts = safe_parts(asset.get("path"))
    if kind in ("path", "font"):
        if parts is None:
            return ("standin" if kind == "font" else "placeholder"), None
        is_addon, hit = _addon_lookup(parts, addons)
        if _usable(kind, hit):
            return "addon", hit
        if is_addon and kind == "path":
            return "placeholder", None
    if extract:
        hit = lookup_extract(extract, ref, asset)
        if _usable(kind, hit):
            return "extract", hit
    if kind == "path":
        factory = STANDINS.get("/".join(_strip_image_ext([p.casefold() for p in parts])))
        return ("standin", factory) if factory else ("placeholder", None)
    return ("standin" if kind == "font" else "placeholder"), None


def _base_name(asset):
    kind = asset.get("kind")
    raw = asset.get("atlas") if kind == "atlas" else asset.get("path") if kind in ("path", "font") else None
    base = os.path.splitext(str(raw or "").replace("\\", "/").rsplit("/", 1)[-1])[0]
    return re.sub(r"[^a-z0-9_.-]+", "_", base.lower())[:64] or "asset"


def write_asset(ref, asset, src, assets_dir):
    """Writes the file for a hit into assets_dir and returns its url relative to the out dir (assets/<name>)."""
    stem = "%s-%s" % (_base_name(asset), hashlib.sha1(ref.encode("utf-8")).hexdigest()[:8])
    if callable(src):
        name, write = stem + ".png", lambda dest: src().save(dest, format="PNG")
    elif asset.get("kind") == "font" or src.suffix.lower() in COPIED_EXTS:
        name, write = stem + src.suffix.lower(), lambda dest: shutil.copyfile(src, dest)
    else:
        name = stem + ".png"

        def write(dest):
            with Image.open(src) as image:
                image.convert("RGBA").save(dest, format="PNG")

    write(assets_dir / name)
    return "assets/" + name


def label_of(asset):
    kind = asset.get("kind")
    if kind == "fileID":
        return "#%s" % asset.get("fileID")
    if kind == "atlas":
        return str(asset.get("atlas"))
    return str(asset.get("path", "")).replace("\\", "/").rsplit("/", 1)[-1].lower()


def missing_name(asset):
    kind = asset.get("kind")
    if kind == "fileID":
        return str(asset.get("fileID"))
    return str(asset.get("atlas") if kind == "atlas" else asset.get("path"))


def resolve_asset(ref, asset, addons, extract, assets_dir):
    """Fills source/url/missing/label of one asset; returns True when it counts as missing."""
    for key in DERIVED:
        asset.pop(key, None)
    source, src = locate(ref, asset, addons, extract)
    if src is not None:
        try:
            asset["url"] = write_asset(ref, asset, src, assets_dir)
        except Exception:  # an undecodable or unwritable file is a missing one, not a reason to abort
            source = "placeholder"
    asset["source"] = source
    if source == "placeholder":
        asset["missing"] = True
        asset["label"] = label_of(asset)
    return source == "placeholder"


def _load(snapshot_path):
    try:
        with open(snapshot_path, encoding="utf-8") as handle:
            snapshot = json.load(handle)
    except OSError as err:
        raise SnapshotError("%s: %s" % (snapshot_path, err.strerror or err))
    except ValueError as err:
        raise SnapshotError("%s: not valid JSON (%s)" % (snapshot_path, err))
    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("assets", {}), dict):
        raise SnapshotError("%s: not a render snapshot (expected an object with assets)" % snapshot_path)
    return snapshot


def resolve_snapshot(snapshot_path, out_dir, extract=None):
    """Rewrites the snapshot in place, writes <out_dir>/assets/*, returns the summary counts."""
    snapshot = _load(snapshot_path)
    addons = snapshot.get("addons") if isinstance(snapshot.get("addons"), dict) else {}
    addons = {str(name).casefold(): root for name, root in addons.items() if isinstance(root, str)}
    assets_dir = Path(out_dir) / "assets"
    try:
        assets_dir.mkdir(parents=True, exist_ok=True)
    except OSError as err:
        raise SnapshotError("%s: %s" % (out_dir, err.strerror or err))
    counts = {"total": 0, "addon": 0, "extract": 0, "standin": 0, "missing": 0}
    missing = []
    for ref, asset in sorted(snapshot.get("assets", {}).items()):
        if not isinstance(asset, dict):
            continue
        if resolve_asset(ref, asset, addons, extract, assets_dir):
            missing.append(missing_name(asset))
        counts["total"] += 1
        counts["missing" if asset["source"] == "placeholder" else asset["source"]] += 1
    old_notes = snapshot.get("notes") if isinstance(snapshot.get("notes"), list) else []
    notes = [n for n in old_notes if n != NO_EXTRACT_NOTE]
    snapshot["notes"] = notes if extract else notes + [NO_EXTRACT_NOTE]
    snapshot["missing"] = sorted(missing)
    tmp = snapshot_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(snapshot, handle, indent=1)
    os.replace(tmp, snapshot_path)
    return counts


def summary_line(counts):
    return "resolved %d assets: %d addon, %d extract, %d stand-in, %d missing" % (
        counts["total"], counts["addon"], counts["extract"], counts["standin"], counts["missing"])
