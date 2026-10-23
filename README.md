# wow-testkit

[![BuyMeACoffee](https://raw.githubusercontent.com/pachadotdev/buymeacoffee-badges/main/bmc-donate-yellow.svg)](https://buymeacoffee.com/f0rty_tw0)

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Where each simulated client behavior comes from is in
[docs/client-sources.md](docs/client-sources.md).

## License

[MIT](LICENSE)
