"""Tests for the exportInterfaceFiles fallback: the exported folders, the CLI hint, and the no-Blizzard-bytes rule."""

import contextlib
import io
import re
import subprocess
from pathlib import Path

from tools.client import art, extract, fakes
from tools.client.__main__ import main
from tools.client.fakes import make_blp
from tools.client.selftest_extract import BUILD_INFO, env

REPO = Path(__file__).resolve().parents[2]
BLIZZARD_BYTES = re.compile(r"\.(blp|ttf|otf|db2)$", re.IGNORECASE)


def exported(tmp):
    inst = fakes.make_install(tmp / "wow", BUILD_INFO)
    fakes.write_export(
        inst / "_retail_",
        code={"Interface/AddOns/Blizzard_Foo/Foo.lua": b"x=1"},
        art={"Interface/Buttons/Red.blp": make_blp((255, 0, 0)), "Interface/Icons/Green.blp": make_blp((0, 255, 0))},
    )
    return inst


def test_fallback_reads_exported_folders_into_the_same_layout(tmp):
    inst = exported(tmp)
    m = extract.run("retail", ["code", "art"], install=inst, home=tmp / "home", from_export=True)
    d = tmp / "home/client/retail/70575"
    assert (d / "code/addons/blizzard_foo/foo.lua").read_bytes() == b"x=1" and m["source"] == "exportInterfaceFiles"
    assert (d / "art/interface/buttons/red.png").is_file()  # prewarmed
    assert art.art_png(d, "interface/icons/green") == d / "art/interface/icons/green.png"  # lazy: reads the export


def test_fallback_art_has_no_by_id(tmp):
    inst = exported(tmp)
    extract.run("retail", ["art"], install=inst, home=tmp / "home", from_export=True)
    assert art.art_png(tmp / "home/client/retail/70575", 12345) is None


def test_missing_export_dir_is_an_error_naming_the_commands(tmp):
    inst = fakes.make_install(tmp / "wow", BUILD_INFO)
    try:
        extract.run("retail", ["code"], install=inst, home=tmp / "home", from_export=True)
    except extract.ExtractError as err:
        assert "exportInterfaceFiles code" in str(err)
        return
    raise AssertionError("expected ExtractError")


def test_export_without_globalstrings_lua_says_so_not_a_listfile_gap(tmp):
    m = extract.run("retail", ["strings"], install=exported(tmp), home=tmp / "home", from_export=True)
    assert m["extracted"]["strings"] == 0
    assert m["notes"] == ["strings: the export holds no globalstrings.lua; GlobalStrings.db2 needs the CASC store"]


def test_failed_casc_open_prints_the_fallback_hint(tmp):
    def broken(install, product):
        raise OSError("boom")

    out, err = io.StringIO(), io.StringIO()
    inst = fakes.make_install(tmp / "wow", BUILD_INFO)
    with env(TESTKIT_HOME=str(tmp / "home"), TESTKIT_WOW_DIR=str(inst)):
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main(["extract", "--listfile", str(fakes.write_listfile(tmp, {}))], open_store=broken)
    lines = err.getvalue().splitlines()
    assert code == 1 and lines[0].startswith("error: CASC store unreadable: ") and "boom" in lines[0], err.getvalue()
    assert lines[1].startswith('fallback: start the game with -console, run "exportInterfaceFiles code"'), lines
    assert lines[1].endswith("then rerun with --from-export")


def test_build_config_without_encoding_prints_the_fallback_hint(tmp):
    inst = fakes.write_install(tmp / "wow", {"wow": [(fakes.ENUS, 0, {})]})
    (config,) = [path for path in (inst / "Data" / "config").rglob("*") if path.is_file()]
    config.write_text("".join(line for line in config.read_text().splitlines(True) if "encoding" not in line))
    out, err = io.StringIO(), io.StringIO()
    with env(TESTKIT_HOME=str(tmp / "home"), TESTKIT_WOW_DIR=str(inst)):
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main(["extract", "--listfile", str(fakes.write_listfile(tmp, {}))])
    lines = err.getvalue().splitlines()
    assert code == 1 and lines[0].startswith("error: CASC store unreadable: ") and "encoding" in lines[0], err.getvalue()
    assert lines[1].startswith("fallback: "), lines


def test_repo_tracks_no_blp_ttf_otf_db2(tmp):
    tracked = subprocess.run(["git", "ls-files"], cwd=REPO, capture_output=True, text=True, check=True).stdout
    assert [name for name in tracked.splitlines() if BLIZZARD_BYTES.search(name)] == []


TESTS = [
    test_fallback_reads_exported_folders_into_the_same_layout,
    test_fallback_art_has_no_by_id,
    test_missing_export_dir_is_an_error_naming_the_commands,
    test_export_without_globalstrings_lua_says_so_not_a_listfile_gap,
    test_failed_casc_open_prints_the_fallback_hint,
    test_build_config_without_encoding_prints_the_fallback_hint,
    test_repo_tracks_no_blp_ttf_otf_db2,
]
