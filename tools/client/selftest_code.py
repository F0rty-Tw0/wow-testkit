"""Tests for the Interface code writer and the GlobalStrings reader/writer."""

import lupa.lua51 as lua51

from tools.client import code, strings
from tools.client.extract import Ctx
from tools.client.fakes import FakeSource
from tools.client.strings import StringsError

CTX_ARGS = dict(flavor="retail", product="wow", build="1", version="1.0.0.1", locales=["enUS"], notes=[])
CTX = Ctx(**CTX_ARGS)


def test_code_writes_only_blizzard_text_files_lowercase(tmp):
    src = FakeSource(
        {
            "interface/addons/blizzard_foo/foo.lua": b"x=1",
            "interface/addons/blizzard_foo/Foo.XML": b"<Ui/>",
            "interface/addons/blizzard_foo/foo.toc": b"## T",
            "interface/addons/blizzard_foo/foo.xsd": b"<s/>",
            "interface/addons/blizzard_foo/readme.txt": b"t",
            "interface/framexml/bar.lua": b"z=3",
            "interface/addons/blizzard_foo/art.blp": b"BLP2",
            "interface/addons/other/o.lua": b"y=2",
        }
    )
    assert code.write(src, tmp / "out", CTX) == 5
    assert (tmp / "out/code/addons/blizzard_foo/foo.lua").read_bytes() == b"x=1"
    assert (tmp / "out/code/addons/blizzard_foo/foo.xml").read_bytes() == b"<Ui/>"
    assert (tmp / "out/code/framexml/bar.lua").read_bytes() == b"z=3"
    assert not (tmp / "out/code/addons/other").exists()
    assert not (tmp / "out/code/addons/blizzard_foo/art.blp").exists()
    assert not (tmp / "out/code/addons/blizzard_foo/readme.txt").exists()


def test_code_refuses_paths_that_escape(tmp):
    src = FakeSource({"interface/addons/blizzard_x/../../../evil.lua": b"z=1"})
    ctx = Ctx(**CTX_ARGS)
    assert code.write(src, tmp / "out", ctx) == 0 and not (tmp / "evil.lua").exists() and ctx.notes


def test_global_strings_parse_edge_cases(tmp):
    text = 'A = "Level %s";\nB = "say \\"hi\\"\\n";\nC = [[two\nlines]];\nD = "\\195\\169";\nN = 5\n'
    assert strings.parse_global_strings(text) == {"A": "Level %s", "B": 'say "hi"\n', "C": "two\nlines", "D": "\u00e9"}


def test_strings_chunk_cannot_reach_os_and_bad_input_is_a_strings_error(tmp):
    for text in ('os.execute("echo hi"); A = "x"', 'A = "unterminated', 'A = "\\255"'):
        try:
            strings.parse_global_strings(text)
        except StringsError:
            continue
        raise AssertionError(f"expected StringsError for {text!r}")


def test_strings_written_per_locale_and_loadable_in_lua51(tmp):
    en = 'A = "x ]] \\\\ \u00e9 \\" end"\nB = "tab\\there"\n'
    src = FakeSource(
        {
            "interface/framexml/enus/globalstrings.lua": en.encode(),
            "interface/framexml/dede/globalstrings.lua": b'A = "de"',
        }
    )
    assert strings.write(src, tmp / "out", CTX) == 2
    assert (tmp / "out/strings/deDE.lua").is_file()
    runtime = lua51.LuaRuntime(encoding=None)
    loaded = runtime.execute((tmp / "out/strings/enUS.lua").read_bytes().decode())
    assert loaded[b"A"].decode() == 'x ]] \\ \u00e9 " end'
    assert loaded[b"B"] == b"tab\there"
    assert strings.to_lua({"B": "\x00\r1", "A": 'q"\\\n'}) == 'return {\n\tA = "q\\"\\\\\\n",\n\tB = "\\000\\r1",\n}\n'


def test_strings_locale_defaults_to_the_installed_one(tmp):
    src = FakeSource({"interface/framexml/globalstrings.lua": b'A = "x"'})
    assert strings.write(src, tmp / "out", CTX) == 1
    assert (tmp / "out/strings/enUS.lua").is_file()


TESTS = [
    test_code_writes_only_blizzard_text_files_lowercase,
    test_code_refuses_paths_that_escape,
    test_global_strings_parse_edge_cases,
    test_strings_chunk_cannot_reach_os_and_bad_input_is_a_strings_error,
    test_strings_written_per_locale_and_loadable_in_lua51,
    test_strings_locale_defaults_to_the_installed_one,
]
