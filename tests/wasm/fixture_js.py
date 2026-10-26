#!/usr/bin/env python3
"""Writes a script a file:// test page loads to get repo files, since pages cannot read them.

    python tests/wasm/fixture_js.py <out.js> <VAR> <dir>...        # var VAR = { "<dir name>": { "<rel/path>": "<text>" } };
    python tests/wasm/fixture_js.py --json <out.js> <VAR> <file>   # var VAR = <the JSON file>;

A file that is not UTF-8 stops it with exit 1 naming the file.
"""

import json
import os
import sys


def read_tree(root):
    files = {}
    for folder, _, names in os.walk(root):
        for name in names:
            path = os.path.join(folder, name)
            with open(path, "rb") as handle:
                raw = handle.read()
            try:
                files[os.path.relpath(path, root).replace("\\", "/")] = raw.decode("utf-8")
            except UnicodeDecodeError:
                sys.exit("not UTF-8: " + path)
    return dict(sorted(files.items()))


def main(argv):
    as_json = argv[:1] == ["--json"]
    out, var, *sources = argv[1:] if as_json else argv
    if as_json:
        with open(sources[0], encoding="utf-8") as handle:
            value = json.load(handle)
    else:
        value = {os.path.basename(os.path.normpath(root)): read_tree(root) for root in sources}
    with open(out, "w", encoding="utf-8") as handle:
        handle.write("var %s = %s;\n" % (var, json.dumps(value)))


if __name__ == "__main__":
    main(sys.argv[1:])
