#!/usr/bin/env bash
# P6: LUA51 for scripts/test.sh that times each run. Runs ${TIMED_BASE:-python tools/run51.py} "$@", appends
# "<ms> <args>" to $BENCH_LOG (when set) and exits with the run's code. Usage:
#   BENCH_LOG="$S/suite-times.txt" LUA51="bash tests/bench/timed51.sh" bash scripts/test.sh; sort -rn "$S/suite-times.txt"
read -r -a BASE <<<"${TIMED_BASE:-python tools/run51.py}"
start=$(date +%s%N)
"${BASE[@]}" "$@"
code=$?
if [[ -n ${BENCH_LOG:-} ]]; then
  echo "$((($(date +%s%N) - start) / 1000000)) $*" >>"$BENCH_LOG"
fi
exit $code
