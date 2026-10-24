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

## Previewing an addon

```bash
bin/tk preview <addon-dir> [--flavor F] [--scenario FILE] [--size WxH] [--out DIR] [--png FILE]
```

Runs the addon on the fake client, then writes what it drew as `<out>/snapshot.json` (frames, textures and text),
copies or stands in for its art under `<out>/assets/`, and with `--png` shoots the result with headless Chrome. Same
prerequisites as the tests above; `--png` also needs Chrome (the Windows install path, `$CHROME`, or `chrome` /
`google-chrome` / `chromium` on `PATH`).

- `--flavor`: game flavor to run (default `retail`).
- `--scenario`: a Lua file returning `{ run = function(s) ... end }`, like the files in `tests/fixtures/scenarios/`. Default: log in.
  `s:snapshot` needs `tk test` and raises an error here.
- `--size`: screen size, `WxH` (default `1920x1080`).
- `--out`: output directory. Default `<home>/preview/<AddonName>`, where `<home>` is `$TESTKIT_HOME`, else
  `%LOCALAPPDATA%/wow-testkit` (Windows), else `~/.cache/wow-testkit`.
- `--png`: also write a PNG of the screen to this file.

Exit codes: `0` clean; `1` the addon or scenario raised an error, or a step failed (the snapshot is still written);
`2` bad usage, unreadable scenario, or the addon is not declared for the flavor.

Shoot an existing output directory again, with a 1px outline and the name on every frame:

```bash
python tools/preview.py png <out> shot.png --outline [--size WxH]
```

To look at a snapshot in a browser, serve it with the viewer over http (the page fetches the snapshot, so a `file://`
page will not do):

```bash
cp -r viewer <out>/viewer
python -m http.server 8000 --bind 127.0.0.1 --directory <out>
# open http://127.0.0.1:8000/viewer/index.html?snapshot=/snapshot.json
```

The page also takes `&zoom=1|fit|<n>`, `&bare=1` (no toolbar) and `&outline=1`.

Limit: there is no Blizzard art yet. Textures from the game client show as labelled placeholders or flat stand-ins,
and `tk preview` prints `note: no client extract`. Art that ships inside the addon is drawn as is.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Where each simulated client behavior comes from is in
[docs/client-sources.md](docs/client-sources.md).

## License

[MIT](LICENSE)
