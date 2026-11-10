"""Tests for the api writer: the extract's own API docs -> <out>/api.lua."""

from tools.client import api
from tools.client.extract import Ctx
from tools.client.fakes import lua_value

DOCS = "code/addons/blizzard_apidocumentationgenerated"
STUB_ENUM = """APIDocumentation:AddDocumentationTable({ Name = "S", Type = "System", Tables = {
  { Name = "X", Type = "Enumeration", NumValues = 1, MinValue = 0, MaxValue = 0,
    Fields = { { Name = "A", Type = "X", EnumValue = 0 } } } } })"""
STUB_CONST = """APIDocumentation:AddDocumentationTable({ Name = "T", Type = "System", Tables = {
  { Name = "Y", Type = "Constants", Values = { { Name = "Z", Type = "number", Value = 5 } } } } })"""


def ctx():
    return Ctx("forever", "wowf", "1", "1.0.0.1", ["enUS"])


def stub_docs(tmp):
    docs = tmp / DOCS
    docs.mkdir(parents=True)
    (docs / "sdocumentation.lua").write_text(STUB_ENUM)
    (docs / "tdocumentation.lua").write_text(STUB_CONST)
    return docs


def test_api_write_turns_docs_into_api_lua(tmp):
    stub_docs(tmp)
    assert api.write(None, tmp, ctx()) == 3  # enums.X, enums.XMeta, constants.Y
    value = lua_value(tmp / "api.lua")
    assert value["enums"]["X"] == {"A": 0} and value["constants"]["Y"] == {"Z": 5}
    assert "XMeta" in value["enums"]


def test_api_write_skips_a_broken_doc_file(tmp):
    (stub_docs(tmp) / "broken.lua").write_text("error('x')")
    assert api.write(None, tmp, ctx()) == 3


def test_api_write_without_docs_notes_and_returns_zero(tmp):
    context = ctx()
    assert api.write(None, tmp, context) == 0
    assert context.notes == ["api: no API docs in the code extract; run --what code first"]
    assert not (tmp / "api.lua").exists()


TESTS = [
    test_api_write_turns_docs_into_api_lua,
    test_api_write_skips_a_broken_doc_file,
    test_api_write_without_docs_notes_and_returns_zero,
]
