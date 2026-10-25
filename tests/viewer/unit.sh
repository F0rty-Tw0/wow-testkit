#!/usr/bin/env bash
# Viewer unit checks: runs tests/viewer/unit.html, and unit_live.html in live mode against a fake backend, in headless
# Chrome over file:// and checks the dumped DOMs.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: unit.sh <scratch-dir>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
mkdir -p "$OUT"
BASE="file:///$(pwd -W 2>/dev/null || pwd)/tests/viewer"
# A private profile keeps headless Chrome away from the running browser.
dump() {
  timeout 60 "$CHROME" --headless=new --disable-gpu --user-data-dir="$OUT/chrome-unit-profile" --virtual-time-budget=3000 --dump-dom "$1" > "$2"
}
dump "$BASE/unit.html" "$OUT/unit.html"
dump "$BASE/unit_live.html?live=1" "$OUT/unit-live.html"
status=0
python tests/viewer/check_unit.py "$OUT/unit.html" || status=1
python tests/viewer/check_unit.py "$OUT/unit-live.html" || status=1
exit $status
