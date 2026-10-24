#!/usr/bin/env bash
# Viewer check: serves viewer/ and the fixture on 127.0.0.1, dumps the DOM and a screenshot with headless Chrome.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: check.sh <scratch-dir>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
PORT=$((20000 + RANDOM % 10000))
STAGE="$OUT/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -r viewer "$STAGE/viewer"; cp tests/viewer/fixtures/basic/snapshot.json "$STAGE/snapshot.json"
python -m http.server "$PORT" --bind 127.0.0.1 --directory "$STAGE" >/dev/null 2>&1 &
SERVER=$!; trap 'kill $SERVER 2>/dev/null || true' EXIT; sleep 1
BASE="http://127.0.0.1:$PORT/viewer/index.html?snapshot=/snapshot.json"
# A private profile keeps headless Chrome away from the user's running browser.
PROFILE="$OUT/chrome-profile"
"$CHROME" --headless=new --disable-gpu --user-data-dir="$PROFILE" --virtual-time-budget=3000 --dump-dom "$BASE" > "$OUT/dom.html"
"$CHROME" --headless=new --disable-gpu --user-data-dir="$PROFILE" --hide-scrollbars --window-size=400,300 --virtual-time-budget=3000 --screenshot="$OUT/basic.png" "$BASE&bare=1"
python tests/viewer/check_dom.py "$OUT/dom.html"
