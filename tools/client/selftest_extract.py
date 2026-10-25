"""Tests for the extractor core: paths, .build.info, listfile cache, manifest and the CLI."""

import contextlib
import io
import json
import os

from tools.client import buildinfo, extract, fakes, manifest, paths
from tools.client.__main__ import main
from tools.client.fakes import FakeCasc

BUILD_INFO = (
    "Branch!STRING:0|Active!DEC:1|Version!STRING:0|Tags!STRING:0|Product!STRING:0\n"
    "eu|1|12.1.5.70575|Windows x86_64 EU? enUS speech?:Windows x86_64 EU? enUS text?|wow\n"
    "eu|1|1.60.1.70532|Windows x86_64 EU? enUS text?|wowf\n"
)
ENV_KEYS = ("TESTKIT_HOME", "LOCALAPPDATA", "HOME", "TESTKIT_WOW_DIR")


@contextlib.contextmanager
def env(**values):
    """Sets exactly the given variables of ENV_KEYS (the rest are removed) for the block."""
    saved = {key: os.environ.get(key) for key in ENV_KEYS}
    for key in ENV_KEYS:
        os.environ.pop(key, None)
    os.environ.update(values)
    try:
        yield
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def empty_store(install, product):
    return FakeCasc({})


def run_cli(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main(list(argv), open_store=empty_store)
    return code, out.getvalue(), err.getvalue()


def run_empty(tmp, flavor="retail", **kw):
    inst = fakes.make_install(tmp / "wow", BUILD_INFO)
    kw.setdefault("listfile_path", fakes.write_listfile(tmp, {}))
    return extract.run(flavor, [], install=inst, home=tmp / "home", open_store=empty_store, **kw)


def test_build_info_row_for_product(tmp):
    row = buildinfo.row_for(buildinfo.parse(BUILD_INFO), "wowf")
    assert (row.version, row.build, row.locales) == ("1.60.1.70532", "70532", ["enUS"])
    assert buildinfo.row_for(buildinfo.parse(BUILD_INFO), "wow").locales == ["enUS"]  # listed twice in Tags


def test_extract_writes_manifest_json_and_lua_that_agree(tmp):
    m = run_empty(tmp, "forever")
    d = tmp / "home" / "client" / "forever" / "70532"
    assert json.loads((d / "manifest.json").read_text()) == m and m["product"] == "wowf"
    assert fakes.lua_value(d / "manifest.lua") == m  # lupa loads the file and converts the table
    tricky = {"s": 'a"b\\c\nd\x01é', "end": [1, "x", True], "a b": {"n": 2.5}, "empty": {}}
    manifest.write(tmp / "tricky", tricky)
    assert fakes.lua_value(tmp / "tricky" / "manifest.lua") == tricky  # quoting, keywords, odd keys, nesting


def test_nothing_is_written_under_the_install(tmp):
    inst = fakes.make_install(tmp / "wow", BUILD_INFO)
    before = sorted(p.relative_to(inst).as_posix() for p in inst.rglob("*"))
    run_empty(tmp)
    assert sorted(p.relative_to(inst).as_posix() for p in inst.rglob("*")) == before


def test_home_resolution_order(tmp):
    with env(TESTKIT_HOME=str(tmp / "a"), LOCALAPPDATA=str(tmp / "b"), HOME=str(tmp / "c")):
        assert paths.testkit_home() == tmp / "a"
    with env(LOCALAPPDATA=str(tmp / "b"), HOME=str(tmp / "c")):
        assert paths.testkit_home() == tmp / "b" / "wow-testkit"
    with env(HOME=str(tmp / "c")):
        assert paths.testkit_home() == tmp / "c" / ".cache" / "wow-testkit"
    # install_dir: the env var wins and must exist; extract_dir and safe_rel are the other path rules
    with env(TESTKIT_WOW_DIR=str(tmp)):
        assert paths.install_dir() == tmp
    with env(TESTKIT_WOW_DIR=str(tmp / "missing")):
        try:
            paths.install_dir()
        except paths.InstallNotFound as err:
            assert "missing" in str(err)
        else:
            raise AssertionError("expected InstallNotFound")
    assert paths.extract_dir(tmp, "forever", "70532") == tmp / "client" / "forever" / "70532"
    assert paths.safe_rel("Interface\\AddOns\\Blizzard_Foo/./Foo.lua") == "interface/addons/blizzard_foo/foo.lua"
    for bad in ("../x", "a/../../x", "/etc/passwd", "C:/x", "c:\\x", "a\0b", "", "//"):
        assert paths.safe_rel(bad) is None, bad


def test_product_not_installed_is_an_error_naming_it(tmp):
    try:
        run_empty(tmp, "vanilla")
    except extract.ExtractError as err:
        assert "wow_classic_era" in str(err) and str(tmp / "wow") in str(err)
        return
    raise AssertionError("expected ExtractError")


def test_stale_extract_is_reported(tmp):
    old = paths.extract_dir(tmp / "home", "retail", "70000")
    manifest.write(old, {"build": "70000"})
    m = run_empty(tmp)
    assert manifest.stale(tmp / "home", "retail", m["build"]) == ["70000"]
    assert manifest.stale(tmp / "home", "retail", "70000") == ["70575"]
    with env(TESTKIT_HOME=str(tmp / "home"), TESTKIT_WOW_DIR=str(tmp / "wow")):
        code, out, _ = run_cli("status", "--flavor", "retail")
    assert (code, out) == (0, "retail: current 70575\n")
    with env(TESTKIT_HOME=str(tmp / "home2"), TESTKIT_WOW_DIR=str(tmp / "wow")):
        manifest.write(paths.extract_dir(tmp / "home2", "retail", "70000"), {"build": "70000"})
        code, out, _ = run_cli("status", "--flavor", "retail")
        assert out == "retail: stale 70000 (installed 70575)\n"
        code, out, _ = run_cli("extract", "--flavor", "retail", "--what", "", "--listfile", str(tmp / "listfile.csv"))
    assert code == 0 and "note: stale extract 70000 (installed build is 70575)" in out, out


def test_listfile_is_fetched_once_and_cached(tmp):
    calls = []

    def fetch(dest, opener=None):
        calls.append(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text("1;a/b.lua\n")
        return {"source": "wowdev/wow-listfile", "tag": "202610240000", "sha256": "abc"}

    first = run_empty(tmp, listfile_path=None, fetch=fetch)
    second = run_empty(tmp, listfile_path=None, fetch=fetch)
    assert len(calls) == 1
    assert first["listfile"] == second["listfile"] and first["listfile"]["tag"] == "202610240000"
    assert calls[0] == tmp / "home" / "listfile" / "community-listfile.csv"


def test_rerun_merges_extracted_kinds(tmp):
    inst = fakes.make_install(tmp / "wow", BUILD_INFO)
    lf = fakes.write_listfile(tmp, {})
    first = {"code": lambda s, o, c: 3}
    second = {"strings": lambda s, o, c: 5}
    kw = dict(install=inst, home=tmp / "home", open_store=empty_store, listfile_path=lf)
    extract.run("retail", ["code"], writers=first, **kw)
    m = extract.run("retail", ["strings"], writers=second, **kw)
    assert m["extracted"] == {"code": 3, "strings": 5}
    assert manifest.read(paths.extract_dir(tmp / "home", "retail", "70575"))["extracted"] == m["extracted"]


def test_cli_status_and_usage_exit_codes(tmp):
    with env(TESTKIT_HOME=str(tmp / "home"), TESTKIT_WOW_DIR=str(tmp / "no-install")):
        assert run_cli("bogus")[0] == 2
        assert run_cli("status", "--flavor", "nope")[0] == 2
        assert run_cli("status") == (0, "retail: none\n", "")
        code, out, err = run_cli("extract", "--what", "bogus")
        assert (code, out, err) == (1, "", "error: unknown --what kind 'bogus'\n")
        assert not (tmp / "home" / "client").exists()  # nothing was created before the kind check


def test_cli_prints_the_manifest_notes_after_the_summary(tmp):
    lf = fakes.write_listfile(tmp, {})
    with env(TESTKIT_HOME=str(tmp / "home"), TESTKIT_WOW_DIR=str(fakes.make_install(tmp / "wow", BUILD_INFO))):
        code, out, _ = run_cli("extract", "--what", "strings", "--listfile", str(lf))
    lines = out.splitlines()
    note = "note: db2: GlobalStrings has no listfile entry in this client"
    assert code == 0 and note in lines and lines.index(note) > lines.index("  strings: 0 files"), out


TESTS = [
    test_build_info_row_for_product,
    test_extract_writes_manifest_json_and_lua_that_agree,
    test_nothing_is_written_under_the_install,
    test_home_resolution_order,
    test_product_not_installed_is_an_error_naming_it,
    test_stale_extract_is_reported,
    test_listfile_is_fetched_once_and_cached,
    test_rerun_merges_extracted_kinds,
    test_cli_status_and_usage_exit_codes,
    test_cli_prints_the_manifest_notes_after_the_summary,
]
