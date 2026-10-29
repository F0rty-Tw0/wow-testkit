#!/usr/bin/env python3
"""The behaviour oracle of the performance rounds (plan 13-performance.md): outputs captured at the base commit, diffed
after each round.

    python tests/bench/oracle.py capture <outdir> --addons <client AddOns dir>
    python tests/bench/oracle.py diff <base> <after>
    python tests/bench/oracle.py --self-check

capture runs, from the repo root through tools/run51.py and bin/tk.lua:
  preview/<name>/   `tk preview` of every folder of tests/fixtures/addons and of tests/fixtures/bench/Stress:
                    snapshot.json and exit.txt (a broken fixture failing is expected and is part of the output)
  smoke/            `tk smoke <outdir>/stage retail --json` on a copy of MouseOverTooltip from --addons: smoke.json, exit.txt
  catalog/          `tk catalog <addons> retail --list <MouseOverTooltip> --blizzard-ui`: catalog.json, exit.txt
diff compares every *.json (parsed) and every exit.txt (text) under both trees by relative path. assets/, stage/ and
.step.log are ignored. Masks, in both trees: loadMs and memoryKb (any depth) -> 0; the catalog date -> ""; the stage
folder -> STAGE and the tree folder -> TREE in every string; kit line numbers ("x.lua:52" -> "x.lua:N") in every string,
but not the lines of addon chunks ("addon:..."). Prints FAIL <file>: <first differing JSON path> per difference, then
PASS oracle (<n> files) or FAIL oracle (<k> differences); exit 1 on any. --self-check runs offline on synthetic trees.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE)).replace("\\", "/")
sys.path.insert(0, os.path.join(ROOT, "tests", "wasm"))

from compare_parity import first_diff  # noqa: E402


def write_json(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(value, handle)


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def make_tree(root, **over):
    """A synthetic capture tree; over replaces one of the fields below."""
    spec = {"x": 1, "status": "pass", "load_ms": 1.5, "memory_kb": 10, "kit_line": 52, "addon_line": 7}
    spec.update({"date": "2026-10-29", "extra": True})
    spec.update(over)
    trace = "boom\nstack traceback:\n\tE:/wow-testkit/addon.lua:%d: in function 'load'\n\taddon:Demo/Main.lua:%d: in main chunk"
    snapshot = {
        "items": [{"id": "f1", "rect": {"x": spec["x"], "y": 2}}],
        "errors": [{"message": trace % (spec["kit_line"], spec["addon_line"])}],
        "dev": {"addons": [{"name": "Demo", "loadMs": spec["load_ms"], "memoryKb": spec["memory_kb"]}]},
    }
    stage = root.replace("\\", "/") + "/stage/MouseOverTooltip"
    write_json(root + "/preview/Demo/snapshot.json", snapshot)
    write_text(root + "/preview/Demo/exit.txt", "0\n")
    write_json(root + "/smoke/smoke.json", {"addons": [{"root": stage, "status": spec["status"]}]})
    write_text(root + "/smoke/exit.txt", "0\n")
    write_json(root + "/catalog/catalog.json", {"date": spec["date"], "smoke": {"status": spec["status"]}})
    write_text(root + "/catalog/exit.txt", "0\n")
    write_text(root + "/preview/Demo/.step.log", "noise %s\n" % spec["load_ms"])
    write_text(root + "/preview/Demo/assets/a.json", "[%s]" % spec["x"])
    if spec["extra"]:
        write_json(root + "/preview/Extra/snapshot.json", {"items": []})


KIT_LINE = re.compile(r"([^\s<>'\"]+\.lua):\d+")
VOLATILE = ("loadMs", "memoryKb")
SKIPPED_PARTS = ("assets", "stage")


def mask_line(hit):
    name = hit.group(1)

    return hit.group(0) if name.lstrip("@").startswith("addon:") else name + ":N"


def mask_text(text, tree):
    """tree is the capture folder (forward slashes): its stage folder reads STAGE, the folder itself TREE."""
    for form, sep in ((tree, "/"), (tree.replace("/", "\\"), "\\")):
        text = text.replace(form + sep + "stage", "STAGE").replace(form, "TREE")

    return KIT_LINE.sub(mask_line, text)


def mask_value(value, tree):
    if isinstance(value, str):
        return mask_text(value, tree)
    if isinstance(value, list):
        return [mask_value(item, tree) for item in value]
    if isinstance(value, dict):
        return {key: 0 if key in VOLATILE else mask_value(item, tree) for key, item in value.items()}

    return value


def read_masked(path, tree):
    with open(path, encoding="utf-8") as handle:
        value = json.load(handle)
    if os.path.basename(path) == "catalog.json" and isinstance(value, dict) and "date" in value:
        value["date"] = ""

    return mask_value(value, tree)


def compared_files(tree):
    """The relative paths (forward slashes) of the *.json and exit.txt files under tree, without assets/, stage/."""
    found = set()
    for folder, dirs, names in os.walk(tree):
        dirs[:] = [name for name in dirs if name not in SKIPPED_PARTS]
        for name in names:
            if name.endswith(".json") or name == "exit.txt":
                found.add(os.path.relpath(os.path.join(folder, name), tree).replace("\\", "/"))

    return found


def normal(path):
    return os.path.abspath(path).replace("\\", "/")


def diff_file(rel, base, after):
    """The first difference of one file as text, or None."""
    left, right = os.path.join(base, rel), os.path.join(after, rel)
    if rel.endswith(".json"):
        found = first_diff(read_masked(left, base), read_masked(right, after))

        return found and "differs at " + found
    with open(left, encoding="utf-8") as one, open(right, encoding="utf-8") as other:
        return None if one.read() == other.read() else "text differs"


def diff_trees(base, after):
    """([FAIL lines], number of files compared) for two capture folders."""
    base, after = normal(base), normal(after)
    left, right = compared_files(base), compared_files(after)
    lines = ["FAIL %s: missing in after" % rel for rel in sorted(left - right)]
    lines += ["FAIL %s: not in base" % rel for rel in sorted(right - left)]
    for rel in sorted(left & right):
        found = diff_file(rel, base, after)
        if found:
            lines.append("FAIL %s: %s" % (rel, found))

    return lines, len(left | right)


def run_diff(base, after):
    lines, count = diff_trees(base, after)
    for line in lines:
        print(line)
    print("FAIL oracle (%d differences)" % len(lines) if lines else "PASS oracle (%d files)" % count)

    return 1 if lines else 0


def tk(*args):
    """tk's exit code and stdout, run from the repo root under lupa's Lua 5.1."""
    command = [sys.executable, "tools/run51.py", "--script", "bin/tk.lua", *args]
    done = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8", errors="replace")

    return done.returncode, done.stdout


def fixture_dirs():
    names = sorted(os.listdir(os.path.join(ROOT, "tests/fixtures/addons")))
    folders = ["tests/fixtures/addons/" + name for name in names]

    return folders + ["tests/fixtures/bench/Stress"]


def capture_previews(out):
    for folder in fixture_dirs():
        target = "%s/preview/%s" % (out, os.path.basename(folder))
        os.makedirs(target, exist_ok=True)
        code, _ = tk("preview", folder, "--out", target)
        write_text(target + "/exit.txt", "%d\n" % code)


def capture_smoke(out, addons):
    shutil.copytree(addons + "/MouseOverTooltip", out + "/stage/MouseOverTooltip")
    code, text = tk("smoke", out + "/stage", "retail", "--json")
    write_text(out + "/smoke/smoke.json", text)
    write_text(out + "/smoke/exit.txt", "%d\n" % code)


def capture_catalog(out, addons):
    write_text(out + "/list.txt", "MouseOverTooltip\n")
    path = out + "/catalog/catalog.json"
    os.makedirs(out + "/catalog", exist_ok=True)
    code, _ = tk("catalog", addons, "retail", "--list", out + "/list.txt", "--out", path, "--blizzard-ui")
    write_text(out + "/catalog/exit.txt", "%d\n" % code)


def capture(out, addons):
    out, addons = normal(out), normal(addons)
    if os.path.isdir(out) and os.listdir(out):
        sys.exit("capture: %s is not empty" % out)
    capture_previews(out)
    capture_smoke(out, addons)
    capture_catalog(out, addons)
    print("captured into " + out)

    return 0


def self_check():
    """Prints PASS self-check when all five cases of the plan behave; else FAIL self-check: <case>. Returns the exit code."""
    cases = [
        ("masked fields only", {"load_ms": 9.5, "memory_kb": 99, "date": "2031-01-01"}, None),
        ("rect.x changed", {"x": 2}, "snapshot.json"),
        ("smoke status flipped", {"status": "fail"}, "smoke.json"),
        ("file removed", {"extra": False}, "snapshot.json"),
        ("kit line only", {"kit_line": 99}, None),
        ("addon line changed", {"addon_line": 8}, "snapshot.json"),
    ]
    with tempfile.TemporaryDirectory() as tmp:
        base = tmp.replace("\\", "/") + "/base"
        make_tree(base)
        for index, (name, over, wants) in enumerate(cases):
            after = tmp.replace("\\", "/") + "/after%d" % index
            make_tree(after, **over)
            lines, _ = diff_trees(base, after)
            hit = [line for line in lines if wants and wants in line]
            if (wants is None and lines) or (wants and not hit):
                print("FAIL self-check: " + name + " " + repr(lines))
                return 1
    print("PASS self-check")
    return 0


def main(argv):
    if argv[:1] == ["--self-check"]:
        return self_check()
    if argv[:1] == ["diff"] and len(argv) == 3:
        return run_diff(argv[1], argv[2])
    if argv[:1] == ["capture"] and len(argv) == 4 and argv[2] == "--addons":
        return capture(argv[1], argv[3])
    sys.exit("usage: oracle.py capture <outdir> --addons <dir> | diff <base> <after> | --self-check")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
