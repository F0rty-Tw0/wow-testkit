#!/usr/bin/env python3
"""Turns bench samples into BENCH lines (plan 13-performance.md). The median is computed only here.

    <bench> | python tests/bench/summarize.py                       # RAW <id> <runtime> <ms> <ms> ... lines on stdin
    python tests/bench/summarize.py --page FILE [--runtime NAME]    # a Chrome page's <pre id="out"> JSON { "<id>": [ms...] }

Prints `BENCH <id> <runtime> n=<n> median=<ms> min=<ms> max=<ms>` per id, in first-seen order; a repeated id and runtime
pools its samples. Other stdin lines pass through unchanged. Exit 1 on a RAW line with no samples or a bad number, or
on a page that never finished (read_side_b of tests/wasm/compare_parity.py).
"""

import os
import statistics
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "wasm"))

from compare_parity import read_side_b  # noqa: E402

DEFAULT_PAGE_RUNTIME = "chrome"


def parse_raw(line):
    """(id, runtime, [samples]) of a RAW line; ValueError when it holds no samples or a bad number."""
    _, bench_id, runtime, *samples = line.split()
    if not samples:
        raise ValueError("no samples in: " + line)

    return bench_id, runtime, [float(sample) for sample in samples]


def summary_line(bench_id, runtime, samples):
    stats = (len(samples), statistics.median(samples), min(samples), max(samples))

    return "BENCH %s %s n=%d median=%.3f min=%.3f max=%.3f" % ((bench_id, runtime) + stats)


def pool(rows):
    """{ (id, runtime): samples } in first-seen order from (id, runtime, samples) rows."""
    pooled = {}
    for bench_id, runtime, samples in rows:
        pooled.setdefault((bench_id, runtime), []).extend(samples)

    return pooled


def read_stdin():
    rows = []
    for line in sys.stdin:
        if line.startswith("RAW "):
            rows.append(parse_raw(line.strip()))
        else:
            print(line.rstrip("\n"))

    return rows


def read_page(path, runtime):
    return [(bench_id, runtime, samples) for bench_id, samples in read_side_b(path).items()]


def main(argv):
    runtime = argv[argv.index("--runtime") + 1] if "--runtime" in argv else DEFAULT_PAGE_RUNTIME
    try:
        rows = read_page(argv[argv.index("--page") + 1], runtime) if "--page" in argv else read_stdin()
    except ValueError as err:
        print("FAIL summarize: " + str(err))
        return 1
    for (bench_id, bench_runtime), samples in pool(rows).items():
        print(summary_line(bench_id, bench_runtime, samples))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
