#!/usr/bin/env python3
"""Bundles the kit, the emcc output and host/worker.js into host/worker_bundle.js (wasm/build.sh runs it).

    python wasm/bundle.py          # writes host/worker_bundle.js from $TK_WASM_CACHE/tk_lua.js (default wasm/.cache)
    python wasm/bundle.py --list   # prints the kit paths the bundle holds

The bundle is `var TK_WORKER_SRC = <JSON string>;` where the string is `var TK_KIT_FILES = {path: text};`, the emcc
output and host/worker.js. The page starts the worker from a Blob of that string, so the worker never fetches a file://
URL. The kit is `git ls-files` minus tests, canaries, viewer, host, wasm and docs, dot-paths and tools subfolders (the
top-level tools/*.lua stay: the kit requires tools.flavors).
"""

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_TOP = ("tests", "canaries", "viewer", "host", "wasm", "docs")


def kit_paths():
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    keep = []
    for path in out.splitlines():
        parts = path.split("/")
        if parts[0] in SKIP_TOP or any(part.startswith(".") for part in parts):
            continue
        if parts[0] == "tools" and len(parts) > 2:
            continue
        keep.append(path)
    return keep


def read_text(path):
    with open(os.path.join(ROOT, path), "rb") as handle:
        raw = handle.read()
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        sys.exit("not UTF-8: " + path)


def main(argv):
    paths = kit_paths()
    if argv == ["--list"]:
        print("\n".join(paths))
        return
    cache = os.environ.get("TK_WASM_CACHE", os.path.join(ROOT, "wasm", ".cache"))
    emcc_out = os.path.join(cache, "tk_lua.js")
    if not os.path.exists(emcc_out):
        sys.exit("missing " + emcc_out + ": run wasm/build.sh")
    with open(emcc_out, encoding="utf-8") as handle:
        module = handle.read()
    files = {path: read_text(path) for path in paths}
    src = "var TK_KIT_FILES = " + json.dumps(files) + ";\n" + module + "\n" + read_text("host/worker.js")
    with open(os.path.join(ROOT, "host", "worker_bundle.js"), "w", encoding="utf-8") as handle:
        handle.write("var TK_WORKER_SRC = " + json.dumps(src) + ";\n")


if __name__ == "__main__":
    main(sys.argv[1:])
