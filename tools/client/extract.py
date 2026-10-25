"""Runs the writers for one flavor over its installed product and records what was written in manifest.json/lua.

Writes only under <home>/client/<flavor>/<build> and the listfile cache; the install is opened read-only.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from tools.client import art, buildinfo, code, db2_export, fallback, fonts, listfile, manifest, paths, strings
from tools.client import casc
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


FALLBACK_HINT = (
    'fallback: start the game with -console, run "exportInterfaceFiles code" and "exportInterfaceFiles art" '
    "at the login screen, then rerun with --from-export"
)


class ExtractError(Exception):
    """A failure to report as `error: <message>`, then `hint` on the next line when there is one."""

    def __init__(self, message, hint=None):
        super().__init__(message)
        self.hint = hint


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


def casc_source(row, install, home, open_store, listfile_path, fetch):
    """(source, close, listfile info) over the installed store; the store is closed again if the listfile fails."""
    try:
        store = open_store(install, row.product)
    except (CascError, CascIndexError, OSError) as err:
        reason = f"{err} ({row.product} in {install})"
        raise ExtractError(f"CASC store unreadable: {reason}", hint=FALLBACK_HINT) from err
    try:
        names, info = open_names(home, listfile_path, fetch)
    except ExtractError:
        store.close()
        raise
    return CascSource(store, names, row.locales), store.close, info


def export_source(flavor, row, install, what):
    try:
        return fallback.open_source(install, flavor, what, row.locales), (lambda: None), None
    except fallback.FallbackError as err:
        raise ExtractError(str(err)) from err


def run(
    flavor,
    what,
    *,
    install,
    home,
    open_store=casc.open_store,
    listfile_path=None,
    fetch=listfile.fetch,
    writers=None,
    from_export=False,
):
    """Extracts the kinds in `what` and returns the manifest. Raises ExtractError. With `from_export` the source is
    the exportInterfaceFiles folders: only code, strings and art can be written; the other kinds get a note."""
    writers = WRITERS if writers is None else writers
    check_kinds(what, writers)
    row = build_row(flavor, install)
    ctx = Ctx(flavor, row.product, row.build, row.version, row.locales, home=Path(home))
    if from_export:
        skipped = [kind for kind in what if kind not in fallback.KINDS]
        ctx.notes += [f"{kind}: not available from {fallback.SOURCE_NAME}" for kind in skipped]
        what = [kind for kind in what if kind not in skipped]
        source, close, info = export_source(flavor, row, install, what)
    else:
        source, close, info = casc_source(row, install, home, open_store, listfile_path, fetch)
    try:
        out = paths.extract_dir(home, flavor, row.build)
        out.mkdir(parents=True, exist_ok=True)
        counts = dict(manifest.read(out).get("extracted", {}))
        for kind in what:
            counts[kind] = writers[kind](source, out, ctx)
    finally:
        close()
    data = {
        "product": row.product,
        "build": row.build,
        "version": row.version,
        "extracted": counts,
        "locales": row.locales,
        "install": Path(install).as_posix(),
        "flavor": flavor,
        "source": fallback.SOURCE_NAME if from_export else "casc",
    }
    if info is not None:
        data["listfile"] = info
    if ctx.notes:
        data["notes"] = ctx.notes
    manifest.write(out, data)
    return data
