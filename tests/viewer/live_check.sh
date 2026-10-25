#!/usr/bin/env bash
# Live viewer check: starts tools/session.py on SessionDemo (temp TESTKIT_HOME, random port), dumps the DOM of
# viewer/index.html?live=1&stream=0 and the DOM and a screenshot of the same page with SessionDemoFrame preselected in
# the inspector, with headless Chrome, checks both DOMs, and stops the server.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: live_check.sh <scratch-dir>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
PORT=$((20000 + RANDOM % 10000))
mkdir -p "$OUT"
HOME_DIR="$(mktemp -d)"
export TESTKIT_HOME="$HOME_DIR"
python tools/session.py tests/fixtures/addons/SessionDemo --port "$PORT" --no-watch > "$OUT/live-server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true; wait $SERVER 2>/dev/null || true; rm -rf "$HOME_DIR"' EXIT
# The server prints `session: http://127.0.0.1:<port>/?token=<token>` once it serves; the data routes need that token.
TOKEN=""
for _ in $(seq 50); do
  TOKEN="$(sed -n 's/^session: .*[?]token=//p' "$OUT/live-server.log" | tr -d '\r')"
  [ -n "$TOKEN" ] && curl -sf -H "X-Session-Token: $TOKEN" "http://127.0.0.1:$PORT/snapshot" > /dev/null && break
  sleep 0.2
done
curl -sf -H "X-Session-Token: $TOKEN" "http://127.0.0.1:$PORT/snapshot" > /dev/null || { echo "FAIL server: no session on port $PORT"; cat "$OUT/live-server.log"; exit 1; }
# token= on the page's own URL sets the session cookie, so the page's requests carry it.
URL="http://127.0.0.1:$PORT/viewer/index.html?live=1&stream=0&token=$TOKEN"
SELECT_URL="$URL&select=SessionDemoFrame&zoom=fit"
# A private profile keeps headless Chrome away from the user's running browser.
PROFILE="$OUT/chrome-live-profile"
timeout 60 "$CHROME" --headless=new --disable-gpu --user-data-dir="$PROFILE" --virtual-time-budget=3000 --dump-dom "$URL" > "$OUT/live.html"
timeout 60 "$CHROME" --headless=new --disable-gpu --user-data-dir="$PROFILE" --window-size=1920,1080 --virtual-time-budget=3000 --dump-dom "$SELECT_URL" > "$OUT/live-select.html"
timeout 60 "$CHROME" --headless=new --disable-gpu --user-data-dir="$PROFILE" --hide-scrollbars --window-size=1920,1080 --virtual-time-budget=3000 --screenshot="$OUT/live.png" "$SELECT_URL"
python tests/viewer/check_live.py "$OUT/live.html" "$OUT/live-select.html"
