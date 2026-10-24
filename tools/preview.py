#!/usr/bin/env python3
"""Preview tooling for the render snapshot.

    python tools/preview.py resolve <snapshot.json> <out-dir> [--extract DIR]
    python tools/preview.py --selftest

resolve rewrites snapshot.json in place and writes <out-dir>/assets/*. Exit 0 whatever is missing;
exit 2 on a usage error or a snapshot that is not JSON.
"""

import sys

USAGE = "usage: preview.py resolve <snapshot.json> <out-dir> [--extract DIR] | preview.py --selftest"


def run_selftest():
    import preview_selftest

    return preview_selftest.run()


def parse_resolve(args):
    """(snapshot, out_dir, extract) from the arguments after `resolve`; None on a usage error."""
    extract = None
    if "--extract" in args:
        at = args.index("--extract")
        if at + 1 >= len(args):
            return None
        extract = args[at + 1]
        args = args[:at] + args[at + 2 :]
    if len(args) != 2:
        return None
    return args[0], args[1], extract


def run_resolve(args):
    import preview_assets

    parsed = parse_resolve(args)
    if parsed is None:
        print(USAGE, file=sys.stderr)
        return 2
    snapshot, out_dir, extract = parsed
    try:
        counts = preview_assets.resolve_snapshot(snapshot, out_dir, extract)
    except preview_assets.SnapshotError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    print(preview_assets.summary_line(counts))
    if extract is None:
        print("note: " + preview_assets.NO_EXTRACT_NOTE)
    return 0


def main(argv):
    if argv == ["--selftest"]:
        return run_selftest()
    if argv and argv[0] == "resolve":
        return run_resolve(argv[1:])
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
