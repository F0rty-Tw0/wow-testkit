"""Fallback reader: the folders `exportInterfaceFiles code|art` writes into a flavour folder, as a Source.

Used when the CASC store cannot be read. The export holds code and art only: no fileIDs, fonts or DB2 tables.
"""

import os
from pathlib import Path

from tools.client import paths

FLAVOR_DIRS = {
    "retail": "_retail_",
    "forever": "_forever_",
    "tbc": "_anniversary_",
    "mists": "_classic_",
    "vanilla": "_classic_era_",
}
SOURCE_NAME = "exportInterfaceFiles"
CODE_DIR = "BlizzardInterfaceCode"
ART_DIR = "BlizzardInterfaceArt"
KINDS = ("code", "strings", "art")  # strings come from an exported GlobalStrings.lua
COMMAND = {"code": "code", "strings": "code", "art": "art"}  # kind -> the exportInterfaceFiles argument


class FallbackError(Exception):
    """The export folder a kind needs is not there."""


class FolderSource:
    """Source over exported folders. Paths are install-relative, lowercase, '/' separated (`interface/...`)."""

    has_db2 = False

    def __init__(self, code_root, art_root, locales):
        self.locales = list(locales)
        self.files = {}
        for root in (code_root, art_root):
            self.scan(Path(root))

    def scan(self, root):
        for folder, _, names in os.walk(root):
            for name in names:
                full = Path(folder) / name
                rel = paths.safe_rel(full.relative_to(root).as_posix())
                if rel is not None and not full.is_symlink():
                    self.files.setdefault(rel, full)

    def paths(self):
        return sorted(self.files)

    def file_id(self, path):
        return None

    def read(self, path, partial=False):
        full = self.files.get((paths.safe_rel(path) or ""))
        return None if full is None else full.read_bytes()

    def read_id(self, file_id, partial=False):
        return None


def roots(install, flavor):
    """(code_root, art_root) of the export in the install's flavour folder."""
    base = Path(install) / FLAVOR_DIRS[flavor]
    return base / CODE_DIR, base / ART_DIR


def open_source(install, flavor, what, locales):
    """FolderSource over the export; FallbackError naming the command when a folder `what` needs is missing."""
    code_root, art_root = roots(install, flavor)
    for kind in what:
        root = art_root if COMMAND[kind] == "art" else code_root
        if not root.is_dir():
            raise FallbackError(
                f'{root} not found; start the game with -console and run "exportInterfaceFiles {COMMAND[kind]}"'
            )
    return FolderSource(code_root, art_root, locales)
