#!/usr/bin/env bash
# Build checks for wasm/build.sh and wasm/bundle.py (needs emcc on PATH). Usage: build_check.sh <scratch-dir>
# Check 1 builds from an empty cache, so it downloads lua-5.1.5.tar.gz from lua.org; copy the tarball into
# "<scratch-dir>/cache" first to stay offline.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: build_check.sh <scratch-dir>}"
CACHE="$OUT/cache"
BUNDLE=host/worker_bundle.js
status=0

# verdict <n> <exit code of the condition> <detail on failure>
verdict() {
  if [[ $2 -eq 0 ]]; then
    echo "PASS $1"
  else
    echo "FAIL $1: $3"
    status=1
  fi
}

mkdir -p "$OUT"
rm -f "$BUNDLE"
TK_WASM_CACHE="$CACHE" bash wasm/build.sh > "$OUT/build1.log" 2>&1
code=$?
count=$(grep -c '^var TK_WORKER_SRC = ' "$BUNDLE" 2>/dev/null)
[[ $code -eq 0 && $count -eq 1 ]]
verdict 1 $? "exit $code, $count TK_WORKER_SRC lines: $(tail -3 "$OUT/build1.log" | tr '\n' ' ')"

listing=$(python wasm/bundle.py --list 2>&1)
wrong=""
for want in toc.lua tools/flavors.lua api/retail/init.lua; do
  grep -qx "$want" <<<"$listing" || wrong="$wrong missing:$want"
done
for banned in tests/run.lua viewer/viewer.js tools/client/atlas.py .luacheckrc; do
  ! grep -qx "$banned" <<<"$listing" || wrong="$wrong present:$banned"
done
[[ -z $wrong ]]
verdict 2 $? "$wrong"

before=$(stat -c %Y "$BUNDLE" 2>/dev/null)
sleep 1
TK_WASM_CACHE="$CACHE" TK_LUA_SHA256=0000000000000000000000000000000000000000000000000000000000000000 bash wasm/build.sh > "$OUT/build3.log" 2>&1
code=$?
after=$(stat -c %Y "$BUNDLE" 2>/dev/null)
grep -q 'sha256 mismatch' "$OUT/build3.log" && ! grep -q 'emcc' "$OUT/build3.log" && [[ $code -eq 1 && $before == "$after" ]]
verdict 3 $? "exit $code, mtime $before -> $after: $(head -3 "$OUT/build3.log" | tr '\n' ' ')"

exit $status
