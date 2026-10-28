#!/usr/bin/env bash
# Run the kit's tests:
#   - every tests/**/test_*.lua on Lua 5.1 ($LUA51, else python tools/run51.py)
#   - the files listed in tests/pure.txt also on the system Lua (lua tests/run.lua)
#   - the runner's --script mode, then the canaries (canaries/run.lua) when present
# Exits non-zero on any failure.

set -uo pipefail
shopt -s globstar nullglob
cd "$(dirname "$0")/.."

# One private temp folder per run, removed on exit: Tmp.dir and tempfile put their folders here, and nothing else
# removes them. Windows tools need a C:/ path, so cygpath converts it when present.
suite_tmp=$(mktemp -d "${TMPDIR:-/tmp}/wow-testkit-suite-XXXXXX")
if command -v cygpath >/dev/null; then
  suite_tmp=$(cygpath -m "$suite_tmp")
fi
export TEMP=$suite_tmp TMP=$suite_tmp TMPDIR=$suite_tmp
cleanup_tmp() {
  if [[ -n $suite_tmp && $suite_tmp == */wow-testkit-suite-* ]]; then
    rm -rf -- "$suite_tmp"
  fi
}
trap cleanup_tmp EXIT

read -r -a RUN51 <<<"${LUA51:-python tools/run51.py}"
passed=0
failed=0

check() {
  if "$@"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
}

script_mode_works() {
  local out code
  out=$("${RUN51[@]}" --script tests/fixtures/exit3.lua a b)
  code=$?
  out=${out//$'\r'/}
  if [[ $code -eq 3 && $out == $'tests/fixtures/exit3.lua\ta\tb' ]]; then
    echo "PASS --script mode"
    return 0
  fi
  echo "FAIL --script mode: exit $code, output: $out"
  return 1
}

for f in tests/**/test_*.lua; do
  check "${RUN51[@]}" "$f"
done

if [[ -f tests/pure.txt ]]; then
  while IFS= read -r f || [[ -n $f ]]; do
    f=${f%$'\r'}
    [[ -n $f ]] && check lua tests/run.lua "$f"
  done <tests/pure.txt
fi

check script_mode_works

if [[ -f canaries/run.lua ]]; then
  check "${RUN51[@]}" --script canaries/run.lua
else
  echo "SKIP canaries (canaries/run.lua not present)"
fi

echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
