#!/usr/bin/env bash
# Parity check (spec T1): the same scripted calls against SessionDemo through SessionHost under lupa (side A) and through
# the worker in headless Chrome over file:// (side B), compared as JSON after masking (compare_parity.py). Builds
# host/worker_bundle.js when it is missing (needs emcc on PATH). Usage: parity.sh <scratch-dir>
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: parity.sh <scratch-dir>}"
mkdir -p "$OUT"
HERE="$(pwd -W 2>/dev/null || pwd)"
[[ -f host/worker_bundle.js ]] || bash wasm/build.sh
python tests/wasm/fixture_js.py "$OUT/fixture_files.js" FIXTURE_FILES tests/fixtures/addons/SessionDemo
python tests/wasm/fixture_js.py --json "$OUT/parity_cases.js" PARITY_CASES tests/wasm/parity_cases.json
python tools/run51.py --script tests/wasm/parity_side_a.lua "$HERE" "$HERE/tests/wasm/parity_cases.json" "$OUT/side_a.json"
rm -rf "$OUT/profile-parity"
export TK_CHROME_PROFILE="$OUT/profile-parity"
bash tests/wasm/run_page.sh "file:///$HERE/tests/wasm/parity.html?fixtures=file:///$OUT/fixture_files.js&cases=file:///$OUT/parity_cases.js" "$OUT/side_b.html"
python tests/wasm/compare_parity.py "$OUT/side_a.json" "$OUT/side_b.html"
