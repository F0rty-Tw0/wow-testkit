"""python -m tools.client extract [--flavor F] [--what KINDS] [--install DIR] [--listfile FILE] | status [--flavor F]"""

import argparse
import sys
from pathlib import Path

from tools.client import casc, extract, manifest, paths


def parser():
    top = argparse.ArgumentParser(prog="tools.client")
    sub = top.add_subparsers(dest="command", required=True)
    for name in ("extract", "status"):
        command = sub.add_parser(name)
        command.add_argument("--flavor", choices=sorted(paths.PRODUCTS), default="retail")
    sub.choices["extract"].add_argument("--what", help="comma-separated kinds; default all")
    sub.choices["extract"].add_argument("--install", type=Path)
    sub.choices["extract"].add_argument("--listfile", type=Path)
    return top


def do_extract(args, open_store):
    what = list(extract.WRITERS) if args.what is None else [kind for kind in args.what.split(",") if kind]
    extract.check_kinds(what, extract.WRITERS)
    try:
        install = args.install or paths.install_dir()
    except paths.InstallNotFound as err:
        raise extract.ExtractError(str(err)) from err
    home = paths.testkit_home()
    data = extract.run(
        args.flavor, what, install=install, home=home, open_store=open_store, listfile_path=args.listfile
    )
    print(f"extracted {args.flavor} {data['build']} to {paths.extract_dir(home, args.flavor, data['build'])}")
    for kind in what:
        print(f"  {kind}: {data['extracted'][kind]} files")
    for old in manifest.stale(home, args.flavor, data["build"]):
        print(f"note: stale extract {old} (installed build is {data['build']})")


def installed_build(flavor):
    """The installed build of the flavor, or None when the install or the product is not there."""
    try:
        return extract.build_row(flavor, paths.install_dir()).build
    except (paths.InstallNotFound, extract.ExtractError):
        return None


def do_status(args):
    home = paths.testkit_home()
    builds = manifest.builds(home, args.flavor)
    current = installed_build(args.flavor)
    if not builds:
        print(f"{args.flavor}: none")
    elif current is None:
        print(f"{args.flavor}: {builds[-1]} (installed build unknown)")
    elif current in builds:
        print(f"{args.flavor}: current {current}")
    else:
        print(f"{args.flavor}: stale {builds[-1]} (installed {current})")


def main(argv=None, open_store=casc.open_store):
    try:
        args = parser().parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as exit_:
        return exit_.code
    try:
        if args.command == "extract":
            do_extract(args, open_store)
        else:
            do_status(args)
    except extract.ExtractError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
