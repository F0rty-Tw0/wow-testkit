#!/usr/bin/env python3
"""Preview tooling for the render snapshot.

    python tools/preview.py resolve <snapshot.json> <out-dir> [--extract DIR]
    python tools/preview.py png <out-dir> <png-file> [--size WxH] [--chrome PATH] [--outline]
    python tools/preview.py --selftest

resolve rewrites snapshot.json in place and writes <out-dir>/assets/*. Exit 0 whatever is missing;
exit 2 on a usage error or a snapshot that is not JSON.
png shoots <out-dir>/snapshot.json with headless Chrome. Exit 0; 2 on a usage error; 3 when Chrome is missing or
wrote no PNG.
"""

import sys

USAGE = (
    "usage: preview.py resolve <snapshot.json> <out-dir> [--extract DIR]"
    " | preview.py png <out-dir> <png-file> [--size WxH] [--chrome PATH] [--outline]"
    " | preview.py --selftest"
)
MAX_SIDE = 16384


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


def parse_size(text):
    """(width, height) from `WxH` with both sides in 1..MAX_SIDE; None otherwise."""
    width, sep, height = text.partition("x")
    if not (sep and width.isdigit() and height.isdigit()):
        return None
    size = int(width), int(height)
    return size if all(0 < side <= MAX_SIDE for side in size) else None


def parse_png(args):
    """(out_dir, png_file, size, chrome, outline) from the arguments after `png`; None on a usage error."""
    size, chrome, outline, positional, i = None, None, False, [], 0
    while i < len(args):
        arg = args[i]
        if arg == "--outline":
            outline = True
        elif arg in ("--size", "--chrome"):
            i += 1
            if i >= len(args):
                return None
            if arg == "--chrome":
                chrome = args[i]
            else:
                size = parse_size(args[i])
                if size is None:
                    return None
        elif arg.startswith("--"):
            return None
        else:
            positional.append(arg)
        i += 1
    if len(positional) != 2:
        return None
    return positional[0], positional[1], size, chrome, outline


def run_png(args):
    import preview_chrome

    parsed = parse_png(args)
    if parsed is None:
        print(USAGE, file=sys.stderr)
        return 2
    out_dir, png_file, size, chrome, outline = parsed
    return preview_chrome.png(out_dir, png_file, size, chrome, outline)


def main(argv):
    if argv == ["--selftest"]:
        return run_selftest()
    if argv and argv[0] == "resolve":
        return run_resolve(argv[1:])
    if argv and argv[0] == "png":
        return run_png(argv[1:])
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
