#!/usr/bin/env bash
# Dumps the DOM of a page in headless Chrome over file://. The page holds its own load event open (tests/wasm/hold.js)
# because --virtual-time-budget and --timeout both dump at load, while a worker still runs.
set -euo pipefail
URL="${1:?usage: run_page.sh <url> <out.html>}"
OUT="${2:?usage: run_page.sh <url> <out.html>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
# A private profile keeps headless Chrome away from the running browser.
PROFILE="${TK_CHROME_PROFILE:-$(dirname "$OUT")/profile}"
timeout 60 "$CHROME" --headless=new --disable-gpu --user-data-dir="$PROFILE" --dump-dom "$URL" > "$OUT"
