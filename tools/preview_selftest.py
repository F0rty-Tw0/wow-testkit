"""Synthetic-file tests for preview_assets and the resolve command. Run: python tools/preview.py --selftest"""

import contextlib
import io
import json
import os
import tempfile
import traceback
from pathlib import Path

from PIL import Image

import preview
import preview_assets as pa

NO_EXTRACT_NOTE = "note: no client extract; art falls back to stand-ins"


def png(path, color=(255, 0, 0, 255)):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (2, 2), color).save(path)
    return path


def tga(path, color=(0, 255, 0)):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (2, 2), color).save(path, format="TGA")


def blp(path, color=(255, 0, 0)):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (4, 4), color).convert("P").save(path, format="BLP")


def path_asset(path):
    return "path:" + path.replace("\\", "/").lower(), {"kind": "path", "path": path.replace("\\", "/")}


def font_asset(path):
    return "font:" + path.replace("\\", "/").lower(), {"kind": "font", "path": path.replace("\\", "/")}


def resolve(tmp, assets, addons=None, extract=None):
    """Writes a snapshot, resolves it, returns (summary counts, snapshot read back, out dir)."""
    snap, out = tmp / "snapshot.json", tmp / "out"
    data = {"assets": dict(assets)}
    if addons is not None:
        data["addons"] = {name: str(root) for name, root in addons.items()}
    snap.write_text(json.dumps(data), encoding="utf-8")
    counts = pa.resolve_snapshot(str(snap), str(out), extract)
    return counts, json.loads(snap.read_text(encoding="utf-8")), out


def pixel(out, url):
    return Image.open(out / url).convert("RGBA").getpixel((0, 0))


def run_main(argv):
    buf, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
        code = preview.main(argv)
    return code, buf.getvalue(), err.getvalue()


def test_addon_png_found_case_insensitively_without_extension(tmp):
    png(tmp / "demo" / "Media" / "ICON.png")
    ref, asset = path_asset("Interface/AddOns/Demo/media/icon")
    _, snap, out = resolve(tmp, {ref: asset}, {"Demo": tmp / "demo"})
    got = snap["assets"][ref]
    assert got["source"] == "addon", got
    assert got["url"].startswith("assets/"), got
    assert pixel(out, got["url"]) == (255, 0, 0, 255)


def test_tga_and_blp_convert_to_png(tmp):
    tga(tmp / "demo" / "a.tga")
    blp(tmp / "demo" / "b.blp")
    ra, a = path_asset("Interface/AddOns/Demo/a")
    rb, b = path_asset("Interface/AddOns/Demo/b.blp")
    (tmp / "demo" / "bad.tga").write_bytes(b"not an image")
    rx, bad = path_asset("Interface/AddOns/Demo/bad")
    _, snap, out = resolve(tmp, {ra: a, rb: b, rx: bad}, {"Demo": tmp / "demo"})
    assert snap["assets"][rx]["source"] == "placeholder" and "url" not in snap["assets"][rx], snap["assets"][rx]
    assert snap["missing"] == ["Interface/AddOns/Demo/bad"], snap["missing"]
    assert snap["assets"][ra]["url"].endswith(".png")
    assert snap["assets"][rb]["url"].endswith(".png")
    assert pixel(out, snap["assets"][ra]["url"]) == (0, 255, 0, 255)
    assert pixel(out, snap["assets"][rb]["url"]) == (255, 0, 0, 255)


def test_missing_addon_file_is_a_labelled_placeholder_and_does_not_abort(tmp):
    png(tmp / "demo" / "Media" / "found.png")
    rf, found = path_asset("Interface/AddOns/Demo/Media/found")
    rm, missing = path_asset("Interface/AddOns/Demo/Media/Missing")
    counts, snap, _ = resolve(tmp, {rf: found, rm: missing}, {"Demo": tmp / "demo"})
    assert snap["assets"][rf]["source"] == "addon"
    got = snap["assets"][rm]
    assert got["source"] == "placeholder" and got["missing"] is True and got["label"] == "missing", got
    assert "url" not in got
    assert snap["missing"] == ["Interface/AddOns/Demo/Media/Missing"], snap["missing"]
    assert "1 missing" in pa.summary_line(counts), pa.summary_line(counts)


def test_path_outside_the_addon_is_refused(tmp):
    png(tmp / "secret.png", (1, 2, 3, 255))
    png(tmp / "elsewhere" / "loot.png", (4, 5, 6, 255))
    (tmp / "demo").mkdir()
    ref, asset = path_asset("Interface/AddOns/Demo/../../secret")
    refs = {ref: asset}
    try:  # a symlink inside the addon pointing out must not be followed
        os.symlink(tmp / "elsewhere", tmp / "demo" / "link", target_is_directory=True)
        r2, a2 = path_asset("Interface/AddOns/Demo/link/loot")
        refs[r2] = a2
    except OSError:
        pass  # no symlink privilege on this machine; the ".." half still runs
    _, snap, out = resolve(tmp, refs, {"Demo": tmp / "demo"})
    for got in snap["assets"].values():
        assert got["source"] == "placeholder", got
    leaked = [f for f in (out / "assets").glob("*") if f.read_bytes() in (
        (tmp / "secret.png").read_bytes(), (tmp / "elsewhere" / "loot.png").read_bytes())]
    assert not leaked, leaked


def test_standins_for_known_paths(tmp):
    ref, asset = path_asset("Interface\\Buttons\\WHITE8X8")
    _, snap, out = resolve(tmp, {ref: asset})
    got = snap["assets"][ref]
    assert got["source"] == "standin", got
    assert pixel(out, got["url"]) == (255, 255, 255, 255)


def test_extract_hit_by_path_and_by_id(tmp):
    png(tmp / "ex" / "art" / "interface" / "foo" / "bar.png")
    png(tmp / "ex" / "art" / "by-id" / "136235.png", (0, 0, 255, 255))
    rp, by_path = path_asset("Interface/Foo/Bar")
    ri, by_id = "id:136235", {"kind": "fileID", "fileID": 136235}
    refs = {rp: by_path, ri: by_id}
    _, snap, out = resolve(tmp, refs, extract=str(tmp / "ex"))
    assert snap["assets"][rp]["source"] == "extract", snap["assets"][rp]
    assert snap["assets"][ri]["source"] == "extract", snap["assets"][ri]
    assert pixel(out, snap["assets"][ri]["url"]) == (0, 0, 255, 255)
    _, bare, _ = resolve(tmp, refs)
    assert bare["assets"][rp]["source"] == "placeholder"
    assert bare["assets"][ri]["source"] == "placeholder"
    assert bare["assets"][ri]["label"] == "#136235"


def test_no_extract_prints_the_note_once(tmp):
    ref, asset = path_asset("Interface/Foo/Bar")
    (tmp / "snapshot.json").write_text(json.dumps({"assets": {ref: asset}}), encoding="utf-8")
    code, out, _ = run_main(["resolve", str(tmp / "snapshot.json"), str(tmp / "out")])
    assert code == 0, code
    assert out.count(NO_EXTRACT_NOTE) == 1, out
    assert "resolved 1 assets: 0 addon, 0 extract, 0 stand-in, 1 missing" in out, out


def test_bad_input_exits_2(tmp):
    bad = tmp / "snapshot.json"
    bad.write_text("not json", encoding="utf-8")
    code, _, err = run_main(["resolve", str(bad), str(tmp / "out")])
    assert code == 2, code
    assert str(bad) in err and "Traceback" not in err, err


def test_font_assets_copy_addon_fonts_only(tmp):
    (tmp / "demo" / "Fonts").mkdir(parents=True)
    (tmp / "demo" / "Fonts" / "x.ttf").write_bytes(b"FONT")
    rh, have = font_asset("Interface\\AddOns\\Demo\\Fonts\\x.ttf")
    rn, lack = font_asset("Fonts\\FRIZQT__.TTF")
    _, snap, out = resolve(tmp, {rh: have, rn: lack}, {"Demo": tmp / "demo"})
    assert snap["assets"][rh]["source"] == "addon"
    assert (out / snap["assets"][rh]["url"]).read_bytes() == b"FONT"
    assert snap["assets"][rn]["source"] == "standin" and "url" not in snap["assets"][rn]
    assert snap["missing"] == []


def test_resolve_twice_gives_the_same_snapshot(tmp):
    png(tmp / "demo" / "icon.png")
    ri, icon = path_asset("Interface/AddOns/Demo/icon")
    rm, gone = path_asset("Interface/AddOns/Demo/gone")
    addons = {"Demo": tmp / "demo"}
    _, first, _ = resolve(tmp, {ri: icon, rm: gone}, addons)
    (tmp / "snapshot.json").write_text(json.dumps(first), encoding="utf-8")
    pa.resolve_snapshot(str(tmp / "snapshot.json"), str(tmp / "out"), None)
    second = json.loads((tmp / "snapshot.json").read_text(encoding="utf-8"))
    assert first == second, (first, second)


TESTS = [
    test_addon_png_found_case_insensitively_without_extension,
    test_tga_and_blp_convert_to_png,
    test_missing_addon_file_is_a_labelled_placeholder_and_does_not_abort,
    test_path_outside_the_addon_is_refused,
    test_standins_for_known_paths,
    test_extract_hit_by_path_and_by_id,
    test_no_extract_prints_the_note_once,
    test_bad_input_exits_2,
    test_font_assets_copy_addon_fonts_only,
    test_resolve_twice_gives_the_same_snapshot,
]


def run():
    passed = failed = 0
    for test in TESTS:
        try:
            with tempfile.TemporaryDirectory() as tmp:
                test(Path(tmp))
            print("PASS " + test.__name__)
            passed += 1
        except Exception:
            print("FAIL " + test.__name__)
            traceback.print_exc()
            failed += 1
    print(f"{passed} passed, {failed} failed")
    return 1 if failed else 0
