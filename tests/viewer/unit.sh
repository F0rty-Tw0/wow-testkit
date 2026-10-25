#!/usr/bin/env bash
# Viewer unit checks: runs tests/viewer/unit.html in headless Chrome over file:// and checks the dumped DOM.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: unit.sh <scratch-dir>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
mkdir -p "$OUT"
# A private profile keeps headless Chrome away from the running browser.
timeout 60 "$CHROME" --headless=new --disable-gpu --user-data-dir="$OUT/chrome-unit-profile" --virtual-time-budget=3000 --dump-dom "file:///$(pwd -W 2>/dev/null || pwd)/tests/viewer/unit.html" > "$OUT/unit.html"
python tests/viewer/check_unit.py "$OUT/unit.html"
