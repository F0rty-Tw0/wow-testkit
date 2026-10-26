#!/usr/bin/env bash
# Host checks (needs host/worker_bundle.js): runs tests/wasm/host.html in headless Chrome over file:// against
# SessionDemo and scores the dump, checks that tests/wasm/unsupported.html shows only the Chromium-only message, and
# takes a 1600x1000 screenshot of host.html?shot=1 into <scratch-dir>/host.png. Usage: host_check.sh <scratch-dir>
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: host_check.sh <scratch-dir>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
mkdir -p "$OUT"
HERE="$(pwd -W 2>/dev/null || pwd)"
FIXTURES="fixtures=file:///$OUT/fixture_files.js"
python tests/wasm/fixture_js.py "$OUT/fixture_files.js" FIXTURE_FILES tests/fixtures/addons/SessionDemo
rm -rf "$OUT/profile-host" "$OUT/profile-unsupported" "$OUT/profile-shot"
status=0
TK_CHROME_PROFILE="$OUT/profile-host" bash tests/wasm/run_page.sh "file:///$HERE/tests/wasm/host.html?$FIXTURES" "$OUT/host.html"
python tests/viewer/check_unit.py "$OUT/host.html" || status=1
TK_CHROME_PROFILE="$OUT/profile-unsupported" bash tests/wasm/run_page.sh "file:///$HERE/tests/wasm/unsupported.html" "$OUT/unsupported.html"
if grep -q 'Chromium only' "$OUT/unsupported.html" && ! grep -q 'id="stage"' "$OUT/unsupported.html"; then
  echo "PASS unsupported: Chromium only"
else
  echo "FAIL unsupported: the body is not only the Chromium-only message"
  status=1
fi
timeout 60 "$CHROME" --headless=new --disable-gpu --user-data-dir="$OUT/profile-shot" --hide-scrollbars --window-size=1600,1000 \
  --screenshot="$OUT/host.png" "file:///$HERE/tests/wasm/host.html?shot=1&$FIXTURES" 2> /dev/null
exit $status
