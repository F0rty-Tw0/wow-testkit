"""`.build.info`: the pipe-separated table the launcher writes next to the install (one parser for the whole package)."""

import re
from typing import NamedTuple

LOCALE = re.compile(r"^[a-z]{2}[A-Z]{2}$")
BUILD = re.compile(r"[0-9]+")


class ProductNotInstalled(Exception):
    """The product has no row in `.build.info`, or its row has a version whose build is not a number."""


class BuildRow(NamedTuple):
    product: str
    version: str
    build: str
    locales: list


def parse(text):
    """Rows as dicts keyed by header name without its `!TYPE:n` suffix."""
    lines = [line for line in text.splitlines() if line.strip()]
    header = [name.split("!")[0] for name in lines[0].split("|")] if lines else []
    return [dict(zip(header, line.split("|"))) for line in lines[1:]]


def pick(rows, product):
    """The product's first Active 1 row, else its first row, else None."""
    mine = [row for row in rows if row.get("Product") == product]
    return next((row for row in mine if row.get("Active") == "1"), mine[0] if mine else None)


def row_for(rows, product):
    row = pick(rows, product)
    if row is None:
        raise ProductNotInstalled(f"product {product!r} is not in .build.info")
    version = row.get("Version", "")
    build = version.rsplit(".", 1)[-1]
    if not BUILD.fullmatch(build):  # the build names the extract folder, so it must not be a path
        raise ProductNotInstalled(f"product {product!r} has version {version!r}, whose build is not a number")
    tokens = row.get("Tags", "").replace(":", " ").split()
    locales = list(dict.fromkeys(token for token in tokens if LOCALE.match(token)))
    return BuildRow(product, version, build, locales)
