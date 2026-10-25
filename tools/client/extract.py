"""Runs the writers for one flavor over its installed product and records what was written in manifest.json/lua.

Writes only under <home>/client/<flavor>/<build> and the listfile cache; the install is opened read-only.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from tools.client import art, buildinfo, code, db2_export, fonts, listfile, manifest, paths, strings
from tools.client.casc import CascError
from tools.client.casc_index import CascIndexError
from tools.client.source import CascSource

# kind -> writer(source, out_dir, ctx) -> file count
WRITERS = {
    "code": code.write,
    "strings": strings.write,
    "art": art.write,
    "db2": db2_export.write,
    "fonts": fonts.write,
}


class ExtractError(Exception):
    """A failure to report as `error: <message>`."""


@dataclass
class Ctx:
    flavor: str
    product: str
    build: str
    version: str
    locales: list
    notes: list = field(default_factory=list)  # writers append what the user should know; kept in the manifest
    home: Optional[Path] = None  # the kit home; writers cache what they download under it


def check_kinds(what, writers):
    for kind in what:
        if kind not in writers:
            raise ExtractError(f"unknown --what kind {kind!r}")


def build_row(flavor, install):
    product = paths.PRODUCTS.get(flavor)
    if product is None:
        raise ExtractError(f"unknown flavor {flavor!r}")
    try:
        text = (Path(install) / ".build.info").read_text(encoding="utf-8")
    except OSError as err:
        raise ExtractError(f"cannot read .build.info in {install}: {err}") from err
    try:
        return buildinfo.row_for(buildinfo.parse(text), product)
    except buildinfo.ProductNotInstalled as err:
        raise ExtractError(f"{err} (flavor {flavor}) in {install}") from err


def open_names(home, listfile_path, fetch):
    try:
        path, info = listfile.ensure(home, listfile_path, fetch)
        return listfile.load(path), info
    except Exception as err:  # network, disk or a bad --listfile: say how to avoid the fetch
        raise ExtractError(f"listfile unavailable ({type(err).__name__}: {err}); pass --listfile FILE") from err


def run(flavor, what, *, install, home, open_store, listfile_path=None, fetch=listfile.fetch, writers=None):
    """Extracts the kinds in `what` and returns the manifest. Raises ExtractError."""
    writers = WRITERS if writers is None else writers
    check_kinds(what, writers)
    row = build_row(flavor, install)
    try:
        store = open_store(install, row.product)
    except (CascError, CascIndexError, OSError) as err:
        raise ExtractError(f"cannot read the {row.product} store in {install}: {err}") from err
    try:
        names, info = open_names(home, listfile_path, fetch)
        out = paths.extract_dir(home, flavor, row.build)
        out.mkdir(parents=True, exist_ok=True)
        source = CascSource(store, names, row.locales)
        ctx = Ctx(flavor, row.product, row.build, row.version, row.locales, home=Path(home))
        counts = dict(manifest.read(out).get("extracted", {}))
        for kind in what:
            counts[kind] = writers[kind](source, out, ctx)
    finally:
        store.close()
    data = {
        "product": row.product,
        "build": row.build,
        "version": row.version,
        "listfile": info,
        "extracted": counts,
        "locales": row.locales,
        "install": Path(install).as_posix(),
        "flavor": flavor,
        "source": "casc",
    }
    if ctx.notes:
        data["notes"] = ctx.notes
    manifest.write(out, data)
    return data
