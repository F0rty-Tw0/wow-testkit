#!/usr/bin/env python3
"""Run kit Lua on Lua 5.1 (lupa) when no lua5.1 binary is installed.

    python tools/run51.py <test.lua>                    # PASS/FAIL banner, exit 0/1
    python tools/run51.py --script <file.lua> [args...] # exit with the chunk's returned number

Hosts tests/run.lua, so both runners share one contract. Adds what plain Lua lacks:
the __tk_fs filesystem bridge (used by fs.lua) and LUA_INIT handling. A test file runs with a private TEMP folder,
removed when it ends.
"""

import os
import shutil
import sys
import tempfile

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
            "replace": os.replace,
        }
    )


def refuse_private(obj, name, is_setting):
    """lupa's attribute_filter: Lua reads or writes no _-prefixed attribute of a Python object (fn.__globals__ is os)."""
    if not isinstance(name, str) or name.startswith("_"):
        raise AttributeError(f"{name!r} is not reachable from Lua")

    return name


def new_runtime(**options):
    """A LuaRuntime with the __tk_fs bridge, no `python` module (global or package.loaded) and no _-prefixed attribute
    reachable from Lua. Client fidelity, not a security boundary: the WoW client has no such names, and addon code is
    trusted."""
    lua = lua51.LuaRuntime(attribute_filter=refuse_private, **options)
    install_fs(lua)
    lua.execute("python = nil; package.loaded.python = nil")

    return lua


def run_lua_init(lua):
    init = os.environ.get("LUA_INIT", "")
    if init.startswith("@"):
        lua.globals().dofile(init[1:])
    elif init:
        lua.execute(init)


def private_temp(lua):
    """Points TEMP, TMP and TMPDIR at a fresh folder that goes when the run ends, so the Tmp.dir folders of one test
    file go with it (scripts/test.sh does the same for a whole run). Lua's os.exit ends the process without Python's
    finally blocks, so it removes the folder first. Returns the folder's remover."""
    folder = tempfile.mkdtemp(prefix="wow-testkit-run-")
    for name in ("TEMP", "TMP", "TMPDIR"):
        os.environ[name] = folder

    def remove():
        shutil.rmtree(folder, ignore_errors=True)

    exits = lua.eval("function(exit, remove) return function(...) remove(); return exit(...) end end")
    lua.globals().os.exit = exits(lua.globals().os.exit, remove)

    return remove


def main(argv):
    lua = new_runtime()
    # --script output (a preview folder, a generated file) may live in TEMP for the caller to keep.
    remove = private_temp(lua) if argv[:1] != ["--script"] else lambda: None
    try:
        run_lua_init(lua)
        lua.globals().arg = lua.table_from({i: a for i, a in enumerate([RUNNER] + argv)})
        runner = lua.execute("return assert(loadfile(...))", RUNNER)
        runner(*argv)  # tests/run.lua ends with os.exit(code)
    except lua51.LuaError as err:
        print(err, file=sys.stderr)
        return 1
    finally:
        remove()
    return 1  # os.exit was not reached


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
