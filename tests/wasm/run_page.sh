#!/usr/bin/env bash
# Dumps the DOM of a page in headless Chrome over file://. The page holds its own load event open (tests/wasm/hold.js)
# because --virtual-time-budget and --timeout both dump at load, while a worker still runs. TK_CHROME_ARGS adds flags
# (split on spaces) and TK_PAGE_TIMEOUT replaces the 60 s limit, for a page that runs longer (tests/wasm/sim_perf.sh).
set -euo pipefail
URL="${1:?usage: run_page.sh <url> <out.html>}"
OUT="${2:?usage: run_page.sh <url> <out.html>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
# A private profile keeps headless Chrome away from the running browser.
PROFILE="${TK_CHROME_PROFILE:-$(dirname "$OUT")/profile}"
read -r -a EXTRA <<< "${TK_CHROME_ARGS:-}"
timeout "${TK_PAGE_TIMEOUT:-60}" "$CHROME" --headless=new --disable-gpu --user-data-dir="$PROFILE" "${EXTRA[@]}" --dump-dom "$URL" > "$OUT"
