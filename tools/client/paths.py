"""Where the extractor reads and writes: the kit home, the client install, and extract-relative paths."""

import os
from pathlib import Path

APP_DIR = "wow-testkit"
PRODUCTS = {
    "retail": "wow",
    "forever": "wowf",
    "tbc": "wow_anniversary",
    "mists": "wow_classic",
    "vanilla": "wow_classic_era",
}
INSTALL_CANDIDATES = ("F:/Battle.net/World of Warcraft", "C:/Program Files (x86)/World of Warcraft")


class InstallNotFound(Exception):
    """No client install at TESTKIT_WOW_DIR or the usual places."""


def testkit_home():
    """TESTKIT_HOME, else <LOCALAPPDATA>/wow-testkit, else <HOME>/.cache/wow-testkit (as src/home.lua)."""
    explicit = os.environ.get("TESTKIT_HOME")
    if explicit:
        return Path(explicit)
    local = os.environ.get("LOCALAPPDATA")
    if local:
        return Path(local) / APP_DIR
    return Path(os.environ.get("HOME") or Path.home()) / ".cache" / APP_DIR


def install_dir():
    """TESTKIT_WOW_DIR (which must exist), else the first existing of INSTALL_CANDIDATES."""
    explicit = os.environ.get("TESTKIT_WOW_DIR")
    if explicit:
        if not Path(explicit).is_dir():
            raise InstallNotFound(f"TESTKIT_WOW_DIR {explicit} is not a directory")
        return Path(explicit)
    for candidate in INSTALL_CANDIDATES:
        if Path(candidate).is_dir():
            return Path(candidate)
    raise InstallNotFound("no World of Warcraft install found; set TESTKIT_WOW_DIR or pass --install")


def extract_dir(home, flavor, build):
    return Path(home) / "client" / flavor / build


def safe_rel(path):
    """`path` lowercased with '/' separators and no '.' parts, or None when it could leave the extract folder
    (parent parts, absolute, drive letter or any ':', NUL) or names nothing."""
    text = path.replace("\\", "/")
    if text.startswith("/") or "\x00" in text or ":" in text:
        return None
    parts = [part for part in text.split("/") if part not in ("", ".")]
    if not parts or ".." in parts:
        return None
    return "/".join(parts).lower()
