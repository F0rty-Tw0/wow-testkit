#!/usr/bin/env bash
# P3b and P4: the worker's call round trips (the four cases of bench_session.py) and its bundle size and start-up, in
# headless Chrome over file:// (tests/bench/wasm_bench.js). Cold = a fresh Chrome profile, warm = the same profile again.
# Prints BENCH lines (tests/bench/summarize.py). Usage: bench_wasm.sh <scratch-dir> [runs]  (scratch-dir a C:/ path)
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: bench_wasm.sh <scratch-dir> [runs]}"
RUNS="${2:-5}"
mkdir -p "$OUT"
HERE="$(pwd -W 2>/dev/null || pwd)"
[[ -f host/worker_bundle.js ]] || bash wasm/build.sh
python tests/wasm/fixture_js.py "$OUT/fixture_files.js" FIXTURE_FILES tests/fixtures/addons/SessionDemo
python tests/wasm/fixture_js.py --json "$OUT/parity_cases.js" PARITY_CASES tests/wasm/parity_cases.json
echo "RAW P4.bytes chrome-wasm $(stat -c %s host/worker_bundle.js)" | python tests/bench/summarize.py
rm -rf "$OUT/profile-bench"
export TK_CHROME_PROFILE="$OUT/profile-bench"
for tag in cold warm; do
  bash tests/wasm/run_page.sh "file:///$HERE/tests/bench/wasm_bench.html?tag=$tag&runs=$RUNS&fixtures=file:///$OUT/fixture_files.js&cases=file:///$OUT/parity_cases.js" "$OUT/wasm_$tag.html"
  python tests/bench/summarize.py --page "$OUT/wasm_$tag.html" --runtime chrome-wasm
done
