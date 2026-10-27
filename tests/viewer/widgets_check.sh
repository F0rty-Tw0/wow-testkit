#!/usr/bin/env bash
# Viewer widget check: serves viewer/ and tests/viewer/widgets_fixture.json on 127.0.0.1, dumps the DOM with headless Chrome
# and asserts the EditBox selection, the reversed, Center and Reverse StatusBar fills and the Slider thumb.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: widgets_check.sh <scratch-dir>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
PORT=$((20000 + RANDOM % 10000))
STAGE="$OUT/widgets-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -r viewer "$STAGE/viewer"; cp tests/viewer/widgets_fixture.json "$STAGE/snapshot.json"
python -m http.server "$PORT" --bind 127.0.0.1 --directory "$STAGE" >/dev/null 2>&1 &
SERVER=$!; trap 'kill $SERVER 2>/dev/null || true' EXIT; sleep 1
BASE="http://127.0.0.1:$PORT/viewer/index.html?snapshot=/snapshot.json"
# A private profile keeps headless Chrome away from the user's running browser.
"$CHROME" --headless=new --disable-gpu --user-data-dir="$OUT/chrome-profile-widgets" --virtual-time-budget=3000 --dump-dom "$BASE" > "$OUT/widgets-dom.html"
python tests/viewer/check_widgets.py "$OUT/widgets-dom.html"
