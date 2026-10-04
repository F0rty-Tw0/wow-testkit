# wow-testkit

Shared offline test kit for World of Warcraft addons: load an addon's Lua outside the game, on every game flavor,
and test it on plain Lua 5.1.

## Running the tests

```bash
bash scripts/test.sh
```

Needs either a Lua 5.1 binary (`LUA51="lua5.1 tests/run.lua" bash scripts/test.sh`) or Python with
[lupa](https://pypi.org/project/lupa/) (`pip install lupa`), plus `lua` (any version) for the pure tests.

Run one file:

```bash
python tools/run51.py tests/test_assert.lua   # Lua 5.1 via lupa
lua tests/run.lua tests/test_assert.lua       # system Lua
```
