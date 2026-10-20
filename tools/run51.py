#!/usr/bin/env python3
"""Run kit Lua on Lua 5.1 (lupa) when no lua5.1 binary is installed.

    python tools/run51.py <test.lua>                    # PASS/FAIL banner, exit 0/1
    python tools/run51.py --script <file.lua> [args...] # exit with the chunk's returned number

Hosts tests/run.lua, so both runners share one contract. Adds what plain Lua lacks:
the __tk_fs filesystem bridge (used by fs.lua) and LUA_INIT handling.
"""

import os
import sys

try:
    from lupa import lua51
except ImportError:
    sys.exit("ERROR: lupa is not installed. Run: pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
RUNNER = ROOT + "/tests/run.lua"


def mkdir_new(path):
    """Creates one directory; False when it already exists (atomic, for claiming unique temp dirs)."""
    try:
        os.mkdir(path)
    except FileExistsError:
        return False
    return True


def install_fs(lua):
    lua.globals().__tk_fs = lua.table_from(
        {
            "list": lambda path: lua.table_from(sorted(os.listdir(path))),
            "exists": os.path.exists,
            "isdir": os.path.isdir,
            "mkdirp": lambda path: os.makedirs(path, exist_ok=True),
            "mkdir": mkdir_new,
        }
    )


def run_lua_init(lua):
    init = os.environ.get("LUA_INIT", "")
    if init.startswith("@"):
        lua.globals().dofile(init[1:])
    elif init:
        lua.execute(init)


def main(argv):
    lua = lua51.LuaRuntime()
    install_fs(lua)
    try:
        run_lua_init(lua)
        lua.globals().arg = lua.table_from({i: a for i, a in enumerate([RUNNER] + argv)})
        runner = lua.execute("return assert(loadfile(...))", RUNNER)
        runner(*argv)  # tests/run.lua ends with os.exit(code)
    except lua51.LuaError as err:
        print(err, file=sys.stderr)
        return 1
    return 1  # os.exit was not reached


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
