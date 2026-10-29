#!/usr/bin/env python3
"""P3a: the round trip of POST /call/<method> to the Python session host (plan 13-performance.md, Task 13.1).

    python tests/bench/bench_session.py [runs]      # default 5; prints RAW lines for tests/bench/summarize.py

Starts SessionDemo under a temp TESTKIT_HOME as session_selftest.running does, then times `runs` calls of each of four
cases of tests/wasm/parity_cases.json, one after the other: [0] snapshot, [1] input click SessionDemoButton, [7] slash
"/sdemo hi", [10] reload. Prints `RAW P3a.<method> cpython+lupa <ms> ...` (wall ms of the whole request).
"""

import json
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from session_selftest import DEMO, post_json, running  # noqa: E402

RUNTIME = "cpython+lupa"
CASE_INDEXES = (0, 1, 7, 10)


def read_cases():
    with open(ROOT / "tests" / "wasm" / "parity_cases.json", encoding="utf-8") as handle:
        cases = json.load(handle)

    return [cases[index] for index in CASE_INDEXES]


def time_call(live, case):
    """Wall ms of one POST /call/<method>; stops on a reply that is not 200 or not ok."""
    start = time.perf_counter()
    status, reply = post_json(live, "/call/" + case["method"], case["req"])
    ms = (time.perf_counter() - start) * 1000
    if status != 200 or reply.get("ok") is False:
        sys.exit("FAIL bench_session: %s -> %s %s" % (case["method"], status, reply))

    return ms


def main(argv):
    runs = int(argv[0]) if argv else 5
    if runs < 1:
        sys.exit("FAIL bench_session: runs must be at least 1")
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        with running(Path(tmp), addon=DEMO) as live:
            for case in read_cases():
                samples = [time_call(live, case) for _ in range(runs)]
                print("RAW P3a.%s %s %s" % (case["method"], RUNTIME, " ".join("%.3f" % ms for ms in samples)))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
