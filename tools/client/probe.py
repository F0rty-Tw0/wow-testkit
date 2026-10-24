"""Probes that tell whether a CASC reader candidate can read the four file types the extractor needs.

    python -m tools.client.probe --candidate NAME --install DIR --products wowf,wow --listfile FILE

Prints `PASS|FAIL <product> <probe> <detail> <seconds>s`. Exit 0 only when every probe passes; 1 when one fails;
2 on a usage error; 3 when the candidate cannot be imported.
"""

import argparse
import importlib
import sys
import time
from typing import NamedTuple

from tools.client import listfile

LUA_PREFIX = "interface/addons/blizzard_"
BLP_PATH = "interface/buttons/white8x8.blp"
DB2_PATH = "dbfilesclient/uitextureatlas.db2"
TTF_PATH = "fonts/frizqt__.ttf"


class ProbeResult(NamedTuple):
    name: str
    ok: bool
    detail: str
    seconds: float


def check_lua(data):
    return b"\n" in data and b"\x00" not in data[:512]


def starts(*magics):
    return lambda data: data.startswith(magics)


def id_of(names, path):
    return next((file_id for file_id, name in names.items() if name == path), None)


def lua_id(store, names):
    """The first Blizzard addon .lua (by path) that this store holds; the listfile spans every build."""
    present = set(store.file_ids())
    found = sorted(
        (name, file_id)
        for file_id, name in names.items()
        if file_id in present and name.startswith(LUA_PREFIX) and name.endswith(".lua")
    )
    return found[0][1] if found else None


# name: (pick the fileID, check the bytes, read partial: DB2 readers skip encrypted sections, so zeros are safe there)
PROBES = {
    "lua": (lua_id, check_lua, False),
    "blp": (lambda store, names: id_of(names, BLP_PATH), starts(b"BLP2", b"BLP1"), False),
    "db2": (lambda store, names: id_of(names, DB2_PATH), starts(b"WDC"), True),
    "ttf": (lambda store, names: id_of(names, TTF_PATH), starts(b"\x00\x01\x00\x00", b"true", b"OTTO"), False),
}


def run_one(name, store, names):
    pick, check, partial = PROBES[name]
    start = time.perf_counter()
    try:
        file_id = pick(store, names)
        if file_id is None:
            return ProbeResult(name, False, "no such file in the listfile or store", time.perf_counter() - start)
        data = store.read(file_id, partial=partial)
        if data is None:
            reason = store.last_error or f"id {file_id} not in store"
            return ProbeResult(name, False, reason, time.perf_counter() - start)
        ok = check(data)
        detail = f"{store.last_error or f'id {file_id}'}, {len(data)} bytes"
        detail += "" if ok else f", wrong content {data[:4]!r}"
    except Exception as err:
        return ProbeResult(name, False, f"{type(err).__name__}: {err}", time.perf_counter() - start)
    return ProbeResult(name, ok, detail, time.perf_counter() - start)


def run_probes(store, names):
    """One ProbeResult per entry of PROBES."""
    return [run_one(name, store, names) for name in PROBES]


def parse(argv):
    parser = argparse.ArgumentParser(prog="probe")
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--install", required=True)
    parser.add_argument("--products", required=True)
    parser.add_argument("--listfile", required=True)
    try:
        return parser.parse_args(argv)
    except SystemExit:
        return None


def main(argv=None):
    args = parse(sys.argv[1:] if argv is None else argv)
    if args is None:
        return 2
    module = "casc" if args.candidate == "casc" else "casc_" + args.candidate
    try:
        adapter = importlib.import_module("tools.client." + module)
    except ImportError as err:
        print(f"candidate '{args.candidate}' not available: {err}", file=sys.stderr)
        return 3
    names = listfile.load(args.listfile)
    failed = False
    for product in args.products.split(","):
        try:
            store = adapter.open_store(args.install, product)
        except Exception as err:
            print(f"FAIL {product} open {type(err).__name__}: {err}")
            failed = True
            continue
        try:
            for result in run_probes(store, names):
                print(f"{'PASS' if result.ok else 'FAIL'} {product} {result.name} {result.detail} {result.seconds:.2f}s")
                failed = failed or not result.ok
        finally:
            store.close()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
