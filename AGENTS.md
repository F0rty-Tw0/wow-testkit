# wow-testkit

Shared offline test kit for World of Warcraft addons. It loads an addon's Lua files outside the game, on all five
game flavors (Retail, the Classic flavors and WoW: Forever), with stubbed WoW APIs, so addon tests run on plain
Lua 5.1 in CI. The kit itself is written in Lua 5.1 and follows the constraints below.

## Constraints

- Lua 5.1 syntax everywhere. Pure modules are also tested on Lua 5.4.
- Every module: `local M = {} ... return M`, 2-space indent, camelCase functions, PascalCase module tables,
  UPPER_CASE constants, no globals. Functions under ~40 lines, files ~300 lines.
- Kit modules are required by repo-relative path (`require("assert")`, `require("ui.widgets")`); every runner puts
  the kit root first on `package.path` (`<root>/?.lua;<root>/?/init.lua`).
- Tests: one behavior per test, named `test_<behavior>`; the test file mirrors the source file; a test file returns
  a function that calls its tests.
- TDD: write the test, run it, watch it fail for the stated reason, implement, watch it pass.
- Filesystem access only through `fs.lua`. Never call `os.execute("mkdir -p ...")` directly elsewhere: on Windows
  Lua routes `os.execute` through cmd.exe.

## Tests

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

## Linting

`stylua --check .` (formatting, `stylua.toml`) and `luacheck .` (semantics, `.luacheckrc`). CI runs both.
