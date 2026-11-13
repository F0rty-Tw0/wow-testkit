#!/usr/bin/env bash
# Spell PNG proof (Task 5.7, AC5; a proof script, not a suite test): starts tools/session.py with the sim and the Blizzard
# UI on a client extract (temp TESTKIT_HOME, random port), then takes two headless Chrome screenshots of the live viewer:
#   spell-<flavor>-mage.png     a Mage mid-Fireball, so the Blizzard cast bar is up and filling;
#   spell-<flavor>-warrior.png  a Warrior meleeing a dummy until the kit's proc lights its glow on the action bar (modern:
#                               Revenge after landed swings; classic: Overpower after a dodge).
# Blizzard frames are DOM, so no WebGL is needed. Look at both PNGs: a missing bar or glow is a bug in the owning unit.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: spell_png.sh <scratch-dir> <flavor> <extract-dir>}"
FLAVOR="${2:?usage: spell_png.sh <scratch-dir> <flavor> <extract-dir>}"
EXTRACT="${3:?usage: spell_png.sh <scratch-dir> <flavor> <extract-dir>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
PORT=$((20000 + RANDOM % 10000))
mkdir -p "$OUT"
HOME_DIR="$(mktemp -d)"
export TESTKIT_HOME="$HOME_DIR"
LOG="$OUT/spell-$FLAVOR-server.log"
python tools/session.py tests/fixtures/addons/SessionDemo --sim --blizzard-ui --extract "$EXTRACT" --flavor "$FLAVOR" \
  --no-watch --port "$PORT" > "$LOG" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true; wait $SERVER 2>/dev/null || true; rm -rf "$HOME_DIR"' EXIT
# The server prints `session: http://127.0.0.1:<port>/?token=<token>` once it serves; the Blizzard UI load takes a while.
TOKEN=""
for _ in $(seq 600); do
  TOKEN="$(sed -n 's/^session: .*[?]token=//p' "$LOG" | tr -d '\r')"
  [ -n "$TOKEN" ] && curl -sf -H "X-Session-Token: $TOKEN" "http://127.0.0.1:$PORT/snapshot" > /dev/null && break
  sleep 0.2
done
curl -sf -H "X-Session-Token: $TOKEN" "http://127.0.0.1:$PORT/snapshot" > /dev/null || { echo "FAIL server: no session on port $PORT"; cat "$LOG"; exit 1; }
# zoom=fit: at 100% the 1080p stage sits below the toolbar and the window crops its bottom rows (the action bar).
URL="http://127.0.0.1:$PORT/viewer/index.html?live=1&stream=0&zoom=fit&token=$TOKEN"

call() {
  curl -sf -H "X-Session-Token: $TOKEN" -H "Content-Type: application/json" -d "$2" "http://127.0.0.1:$PORT/call/$1"
}
sim() {
  call sim "$1"
}
key() {
  call input "{\"kind\":\"keydown\",\"key\":\"$1\"}" > /dev/null
  call input "{\"kind\":\"keyup\",\"key\":\"$1\"}" > /dev/null
}
# A click on the mob in the 3D world (empty screen corner, so no frame takes it); $2 is the mouse button.
clickMob() {
  call input "{\"kind\":\"click\",\"target\":{\"x\":1900,\"y\":1000},\"world\":{\"guid\":\"$1\"},\"button\":\"$2\"}" > /dev/null
}
# A dummy 20 yd ahead of the spawn (0, -10) that never swings back; prints its guid.
dummy() {
  sim '{"action":"spawn","pos":{"x":0,"y":10},"health":100000,"ai":false}' | python -c "import json,sys; print(json.load(sys.stdin)['guid'])"
}
# Whether a proc glow is lit: the world reply's overlays (SimWorld). A /run print cannot answer over the wire: with the
# Blizzard UI, its own /run takes the line and prints to its chat frame, not the session console.
glowed() {
  sim '{"action":"world"}' | python -c "import json,sys; sys.exit(0 if json.load(sys.stdin)['world']['overlays'] else 1)"
}
# Whether the viewer's snapshot draws that glow: a proc atlas texture (Blizzard's ActionButtonSpellAlerts, forever and
# tbc) with effective alpha > 0 inside an ActionButton<n>. Prints the button names; the sim's overlays alone do not prove
# the action bar shows it.
glowDrawn() {
  curl -sf -H "X-Session-Token: $TOKEN" "http://127.0.0.1:$PORT/snapshot" | python -c "
import json, re, sys
items = json.load(sys.stdin)['items']
byId = {i['id']: i for i in items}
def button(i):
    while i:
        if re.fullmatch(r'ActionButton\d+', i.get('name') or ''):
            return i['name']
        i = byId.get(i.get('parent'))
lit = sorted({button(i) for i in items
              if str(i.get('atlas', '')).startswith('atlas:ui-hud-actionbar-proc-') and i.get('alpha', 0) > 0} - {None})
print(' '.join(lit))
sys.exit(0 if lit else 1)"
}
# The open page steps the sim itself (a step every 100 ms), so the time budget is how far the sim runs before the shot.
shot() {
  timeout 120 "$CHROME" --headless=new --disable-gpu --user-data-dir="$OUT/chrome-spell-profile" --hide-scrollbars \
    --window-size=1920,1080 --virtual-time-budget="$2" --screenshot="$OUT/$1" "$URL"
}

# Mage: target the dummy, Fireball from slot 1 (key 1), then 0.6 s of the 1.5 s cast here. With stream=0 the page draws
# the UI once, from the snapshot it reads at load, so the bar shows what the sim reached before the shot (~40% filled);
# a short budget keeps the page's own steps inside the cast.
sim '{"action":"reset","class":"MAGE"}' > /dev/null
MOB="$(dummy)"
clickMob "$MOB" LeftButton
key 1
for _ in 1 2 3; do
  sim '{"action":"step","seconds":0.2}' > /dev/null
done
shot "spell-$FLAVOR-mage.png" 600

# Warrior: Charge (slot 1) to the dummy, attack it, swing until the proc glows (at most 60 s of sim time).
sim '{"action":"reset","class":"WARRIOR"}' > /dev/null
MOB="$(dummy)"
clickMob "$MOB" LeftButton
key 1
clickMob "$MOB" RightButton
for _ in $(seq 240); do
  sim '{"action":"step","seconds":0.25}' > /dev/null
  glowed && break
done
if ! glowed; then
  echo "FAIL no proc glow after 60 s of swings; world and console tail:"
  sim '{"action":"world"}'
  echo
  call console '{"since":0}' | python -c "import json,sys; [print(json.dumps(l)) for l in json.load(sys.stdin)['lines'][-8:]]"
  exit 1
fi
LIT="$(glowDrawn)" || { echo "FAIL the sim has a proc overlay but the snapshot draws no proc glow on an ActionButton"; exit 1; }
shot "spell-$FLAVOR-warrior.png" 1000
echo "PASS spell_png $FLAVOR (glow on $LIT): $OUT/spell-$FLAVOR-mage.png $OUT/spell-$FLAVOR-warrior.png"
