"""Blizzard art to PNG: BLP, TGA and PNG are decoded by Pillow, cached under <extract>/art, most of it on demand.

Cache layout: art/<path without extension>.png and art/by-id/<fileID>.png.
"""

import atexit
import io
import os
import struct
from pathlib import Path

from PIL import Image

from tools.client import casc, fallback, listfile, manifest, paths
from tools.client.casc_index import CascIndexError
from tools.client.source import CascSource

PREWARM = (
    "interface/buttons/",
    "interface/tooltips/",
    "interface/dialogframe/",
    "interface/minimap/",
    "interface/chatframe/",
)
SOURCE_SUFFIXES = (".blp", ".tga")
FORMATS = ("PNG", "BLP", "TGA")
_sources = {}  # extract dir -> Source or None, so one process opens a store once


def to_png_bytes(image):
    out = io.BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()


def raw_bgra_blp(data):
    """The first mip of a BLP2 stored as raw BGRA (encoding 3), which Pillow cannot read; None for other files."""
    if data[:4] != b"BLP2" or len(data) < 28 or data[8] != 3:
        return None
    width, height, offset = struct.unpack_from("<3I", data, 12)  # width, height, first mip offset
    return Image.frombuffer("RGBA", (width, height), data[offset : offset + width * height * 4], "raw", "BGRA", 0, 1)


def decode_to_png(data):
    """PNG bytes of a BLP, TGA or PNG image. Raises ValueError("unsupported image") for anything else."""
    try:
        image = raw_bgra_blp(data)
        if image is not None:
            return to_png_bytes(image)
        with Image.open(io.BytesIO(data), formats=FORMATS) as image:
            return to_png_bytes(image.convert("RGBA"))
    except Exception as err:  # Pillow raises many types for a bad file; they all mean the same here
        raise ValueError("unsupported image") from err


def lazy_source(extract_dir):
    """The store the extract was made from, opened read-only from its manifest; None when it cannot be."""
    key = str(Path(extract_dir).resolve())
    if key not in _sources:
        _sources[key] = open_from_manifest(Path(extract_dir).resolve())
    return _sources[key]


def open_from_manifest(extract_dir):
    info = manifest.read(extract_dir)
    if not info.get("install") or not info.get("product"):
        return None
    if info.get("source") == fallback.SOURCE_NAME:
        code_root, art_root = fallback.roots(info["install"], info["flavor"])
        return fallback.FolderSource(code_root, art_root, info.get("locales", []))
    try:
        store = casc.open_store(info["install"], info["product"])
    except (casc.CascError, CascIndexError, OSError):
        return None
    atexit.register(store.close)
    home = extract_dir.parents[2] if len(extract_dir.parents) > 2 else extract_dir
    cached = home / "listfile" / listfile.ASSET  # path -> fileID needs the listfile the extract was made with
    names = listfile.load(cached) if cached.is_file() else {}
    return CascSource(store, names, info.get("locales", []))


def cache_path(extract_dir, key):
    """art/<key>.png or art/by-id/<id>.png; None for a key that could leave the extract."""
    if isinstance(key, int):
        return Path(extract_dir) / "art" / "by-id" / f"{key}.png"
    rel = paths.safe_rel(key)
    return None if rel is None else Path(extract_dir) / "art" / f"{rel}.png"


def write_png(target, data):
    target.parent.mkdir(parents=True, exist_ok=True)
    part = target.with_name(target.name + ".part")
    part.write_bytes(data)
    os.replace(part, target)


def art_png(extract_dir, key, *, source=None):
    """The cached PNG for `key` (a lowercase path without extension, or an int fileID), decoded from the source
    on a miss. None when the file is absent or undecodable, or when the install cannot be opened."""
    target = cache_path(extract_dir, key)
    if target is None:
        return None
    if target.is_file():
        return target
    source = source or lazy_source(extract_dir)
    if source is None:
        return None
    if isinstance(key, int):
        data = source.read_id(key)
    else:
        data = next((d for d in (source.read(key + ext) for ext in SOURCE_SUFFIXES) if d is not None), None)
    if data is None:
        return None
    try:
        write_png(target, decode_to_png(data))
    except ValueError:
        return None
    return target


def write(source, out, ctx):
    """Decodes every BLP and TGA under the PREWARM prefixes to <out>/art; returns the PNGs written."""
    written, failed, seen = 0, [], set()
    for path in source.paths():
        if not path.startswith(PREWARM) or not path.endswith(SOURCE_SUFFIXES):
            continue
        stem = path[: path.rindex(".")]
        target = cache_path(out, stem)
        if target is None:
            ctx.notes.append(f"art: skipped unsafe path {path!r}")
            continue
        if stem in seen:  # a .blp wins over a .tga of the same name
            continue
        seen.add(stem)
        data = source.read(path)
        try:
            if data is None:
                raise ValueError("unreadable")
            write_png(target, decode_to_png(data))
        except ValueError:
            failed.append(path)
        else:
            written += 1
    if failed:
        ctx.notes.append(f"art: {len(failed)} files did not read or decode (first: {failed[0]})")
    return written
