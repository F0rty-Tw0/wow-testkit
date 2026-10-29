#!/usr/bin/env bash
# P5: the draw time of the Stress fixture's snapshot (6000+ items) in the viewer, in headless Chrome over file://
# (tests/bench/viewer_draw.js). Prints BENCH lines (tests/bench/summarize.py). Usage: bench_viewer.sh <scratch-dir> [runs]
# (scratch-dir a C:/ path; the page goes through tests/wasm/run_page.sh, whose hold.js keeps performance.now() real, unlike
# --virtual-time-budget)
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: bench_viewer.sh <scratch-dir> [runs]}"
RUNS="${2:-5}"
mkdir -p "$OUT"
HERE="$(pwd -W 2>/dev/null || pwd)"
rm -rf "$OUT/viewer-stress"
python tools/run51.py --script bin/tk.lua preview tests/fixtures/bench/Stress --out "$OUT/viewer-stress" > /dev/null
python tests/wasm/fixture_js.py --json "$OUT/viewer_snapshot.js" SNAPSHOT "$OUT/viewer-stress/snapshot.json"
export TK_CHROME_PROFILE="$OUT/profile-viewer"
bash tests/wasm/run_page.sh "file:///$HERE/tests/bench/viewer_draw.html?live=1&runs=$RUNS&snap=file:///$OUT/viewer_snapshot.js&base=file:///$OUT/viewer-stress/snapshot.json" "$OUT/viewer_draw.html"
python tests/bench/summarize.py --page "$OUT/viewer_draw.html" --runtime chrome-viewer
