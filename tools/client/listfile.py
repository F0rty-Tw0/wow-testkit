"""Community listfile (wowdev/wow-listfile): fileID -> path, fetched once and cached under the kit home by ensure."""

import hashlib
import json
import os
import urllib.request
from pathlib import Path

API = "https://api.github.com/repos/wowdev/wow-listfile/releases/latest"
ASSET = "community-listfile.csv"
USER_AGENT = "wow-testkit"


def load(path):
    """{fileID: lowercase path with '/'} from `id;path` lines; lines that do not parse are skipped."""
    names = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            head, sep, tail = line.rstrip("\r\n").partition(";")
            if not sep or not head.isdigit() or not tail:
                continue
            names[int(head)] = tail.replace("\\", "/").lower()
    return names


def get(opener, url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with opener(request) as response:
        return response.read()


def fetch(dest, opener=urllib.request.urlopen):
    """Downloads the latest listfile release asset to `dest`; returns {source, tag, sha256}."""
    release = json.loads(get(opener, API))
    asset = next(a for a in release["assets"] if a["name"] == ASSET)
    data = get(opener, asset["browser_download_url"])
    dest = os.fspath(dest)
    os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
    part = dest + ".part"
    with open(part, "wb") as handle:
        handle.write(data)
    os.replace(part, dest)
    return {"source": "wowdev/wow-listfile", "tag": release["tag_name"], "sha256": hashlib.sha256(data).hexdigest()}


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure(home, path=None, fetch=fetch):
    """(listfile path, info): `path` when given (info {source: local, sha256}), else the copy cached under
    <home>/listfile, fetched on the first call only."""
    if path is not None:
        return Path(path), {"source": "local", "sha256": sha256_of(path)}
    cache = Path(home) / "listfile" / ASSET
    meta = cache.with_name("listfile.json")
    if cache.is_file() and meta.is_file():
        try:
            return cache, json.loads(meta.read_text(encoding="utf-8"))
        except ValueError:
            pass  # a damaged note about the cache: fetch again
    info = fetch(cache)
    meta.write_text(json.dumps(info, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return cache, info
