#!/usr/bin/env bash
# AC6 proof (a manual script, not a suite test: it needs a client extract): times `sim step` in the WASM worker in
# headless Chrome (tests/wasm/sim_perf.js), kit-only without an extract, with Blizzard's UI loaded from it with one.
# The extract is never copied: its file list goes into <scratch-dir>/extract_files.js and the page reads the files in
# place over file://. Builds host/worker_bundle.js when it is missing (needs emcc on PATH).
# Usage: sim_perf.sh <scratch-dir> [<extract-dir>]. Prints the page's JSON result; exits 1 when the page failed.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: sim_perf.sh <scratch-dir> [<extract-dir>]}"
EXTRACT="${2:-}"
mkdir -p "$OUT"
HERE="$(pwd -W 2>/dev/null || pwd)"
[[ -f host/worker_bundle.js ]] || bash wasm/build.sh
python tests/wasm/fixture_js.py "$OUT/fixture_files.js" FIXTURE_FILES tests/fixtures/addons/SessionDemo
QUERY="fixtures=file:///$OUT/fixture_files.js"
if [[ -n "$EXTRACT" ]]; then
  python - "$EXTRACT" "$OUT/extract_files.js" <<'PY'
import json, os, sys
root, out = os.path.abspath(sys.argv[1]), sys.argv[2]
paths = sorted(os.path.relpath(os.path.join(d, n), root).replace("\\", "/") for d, _, names in os.walk(root) for n in names)
base = "file:///" + root.replace("\\", "/").lstrip("/") + "/"
with open(out, "w", encoding="utf-8") as handle:
    handle.write("var EXTRACT_FILES = %s;\n" % json.dumps({"base": base, "paths": paths}))
PY
  QUERY="$QUERY&extract=file:///$OUT/extract_files.js&hold=280000"
  export TK_CHROME_ARGS="--allow-file-access-from-files"
  export TK_PAGE_TIMEOUT=300
fi
rm -rf "$OUT/profile-sim-perf"
export TK_CHROME_PROFILE="$OUT/profile-sim-perf"
bash tests/wasm/run_page.sh "file:///$HERE/tests/wasm/sim_perf.html?$QUERY" "$OUT/sim_perf.html"
python - "$OUT/sim_perf.html" <<'PY'
import html, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
found = re.search(r'<pre id="out"[^>]*>(.*?)</pre>', text, re.S)
body = html.unescape(found.group(1)) if found else "FAIL sim_perf: no #out in the dump"
print(body)
sys.exit(1 if body.startswith("FAIL") or not body.strip() else 0)
PY
