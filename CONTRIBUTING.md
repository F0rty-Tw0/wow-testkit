# Contributing

The kit is written in Lua 5.1 and runs addon tests outside the game on plain Lua 5.1 in CI.

## Code constraints

- Lua 5.1 syntax everywhere. Pure modules are also tested on Lua 5.4.
- Every module: `local M = {} ... return M`, 2-space indent, camelCase functions, PascalCase module tables,
  UPPER_CASE constants, no globals. Functions under ~40 lines, files ~300 lines.
- Kit modules are required by repo-relative path (`require("assert")`, `require("ui.widgets")`); every runner puts
  the kit root first on `package.path` (`<root>/?.lua;<root>/?/init.lua`).
- Filesystem access only through `fs.lua`. Never call `os.execute("mkdir -p ...")` directly elsewhere: on Windows
  Lua routes `os.execute` through cmd.exe.
- A fake that simulates client behavior cites its source: add a row to `docs/client-sources.md` with the Blizzard
  `path:line` or wiki page, and name the test of an `assumed` row with the suffix `_assumed`.

## Tests

- One behavior per test, named `test_<behavior>`; the test file mirrors the source file; a test file returns a
  function that calls its tests.
- Write the test first, run it and watch it fail for the stated reason, then implement and watch it pass.

```bash
bash scripts/test.sh                                   # everything; non-zero exit on any failure
python tools/run51.py tests/test_assert.lua            # one file on Lua 5.1 (lupa: pip install lupa)
lua tests/run.lua tests/test_assert.lua                # one file on the system Lua
python tools/run51.py --script <file.lua> [args...]    # run a script; exits with its returned number
LUA51="lua5.1 tests/run.lua" bash scripts/test.sh      # use a real Lua 5.1 binary instead of lupa
```

- `tests/pure.txt` lists the test files that must also pass on the system Lua (5.4).
- `tools/run51.py` hosts `tests/run.lua` on lupa's Lua 5.1 and adds the `__tk_fs` filesystem bridge and
  `LUA_INIT=@file` handling.

## API manifests

`api/` is generated; never edit it by hand. `tools/fetch.sh` mirrors a branch's Blizzard API docs and Ketho's name
lists into the testkit home, and `tools/generate.lua` turns the mirror into `api/<flavor>/` plus `api/versions.lua`.

```bash
bash tools/fetch.sh classic_era                         # the commits api/versions.lua records: regenerates as committed
bash tools/fetch.sh classic_era --latest                # both branch tips: a deliberate data bump
GETHE_COMMIT=<sha> bash tools/fetch.sh live             # one exact Gethe commit (full SHA); KETHO_COMMIT likewise
python tools/run51.py --script tools/generate.lua vanilla
```

## Linting

`stylua --check .` (formatting, `stylua.toml`) and `luacheck .` (semantics, `.luacheckrc`). CI runs both.
