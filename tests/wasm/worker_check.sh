#!/usr/bin/env bash
# Worker core checks (needs host/worker_bundle.js): runs tests/wasm/worker.html in headless Chrome over file:// against
# SessionDemo and scores the dump. Usage: worker_check.sh <scratch-dir>
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: worker_check.sh <scratch-dir>}"
mkdir -p "$OUT"
HERE="$(pwd -W 2>/dev/null || pwd)"
python tests/wasm/fixture_js.py "$OUT/fixture_files.js" FIXTURE_FILES tests/fixtures/addons/SessionDemo
rm -rf "$OUT/profile-worker"
export TK_CHROME_PROFILE="$OUT/profile-worker"
bash tests/wasm/run_page.sh "file:///$HERE/tests/wasm/worker.html?fixtures=file:///$OUT/fixture_files.js" "$OUT/worker.html"
python tests/viewer/check_unit.py "$OUT/worker.html"
