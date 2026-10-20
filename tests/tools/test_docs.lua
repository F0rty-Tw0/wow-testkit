local A = require("assert")
local Docs = require("tools.docs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local DOCS_DIR = TEST_DIR .. "/../fixtures/docs"
local BAD_DIR = TEST_DIR .. "/../fixtures/docs_bad"
local UNSETTLED_DIR = TEST_DIR .. "/../fixtures/docs_unsettled"
local UNRESOLVED_DIR = TEST_DIR .. "/../fixtures/docs_unresolved"

local function docNamed(entries, name)
  for _, entry in ipairs(entries) do
    if entry.doc.Name == name then
      return entry
    end
  end
  error("no doc named " .. name)
end

local entries, errors, report = Docs.loadDir(DOCS_DIR)
local usesEnum = docNamed(entries, "UsesEnum").doc

local function test_load_dir_loads_only_lua_files()
  A.eq(#entries, 5)
end

local function test_load_dir_reports_no_errors_for_valid_docs()
  A.same(errors, {})
end

local function test_entry_names_its_source_file()
  A.eq(docNamed(entries, "Unit").file, "UnitDocumentation.lua")
end

local function test_captured_doc_keeps_its_shape()
  local unit = docNamed(entries, "Unit").doc
  A.eq(unit.Functions[2].Arguments[2].Default, true)
  A.eq(unit.Events[1].LiteralName, "UNIT_HEALTH")
end

local function test_enum_reference_resolves_to_enum_value()
  A.eq(usesEnum.EnumField, 1)
end

local function test_enum_arithmetic_resolves()
  A.eq(usesEnum.EnumSum, 3)
end

local function test_constant_reference_resolves()
  A.eq(usesEnum.ConstantProduct, 20)
end

local function test_constant_chained_through_other_constants_resolves()
  A.eq(usesEnum.ChainedConstant, 16)
end

local function test_enum_typed_string_constant_resolves_to_enum_value()
  A.eq(usesEnum.EnumTypedConstant, 0)
end

local function test_cstring_constant_stays_a_string()
  A.eq(usesEnum.StringConstant, "XVV")
end

local function test_enum_meta_resolves_to_num_values()
  A.eq(usesEnum.EnumMeta, 2)
end

local function test_report_counts_passes_until_settled()
  A.eq(report.settled, true)
  A.eq(report.passes, 4)
end

local function test_broken_file_is_reported_with_its_filename()
  local badEntries, badErrors = Docs.loadDir(BAD_DIR)
  A.eq(#badEntries, 0)
  A.eq(#badErrors, 1)
  A.eq(badErrors[1].file, "BrokenDocumentation.lua")
  A.contains(badErrors[1].err, "BrokenDocumentation.lua")
end

local function test_unsettled_values_are_reported_after_max_passes()
  local unsettledEntries, _, unsettledReport = Docs.loadDir(UNSETTLED_DIR)
  A.eq(unsettledReport.settled, false)
  A.eq(unsettledReport.passes, 10)
  A.contains(unsettledReport.notes[1], "Constants.Loop.N")
  A.eq(#unsettledEntries, 1, "the docs from the final pass are still returned")
end

local function test_unresolved_reference_is_reported_and_loads_as_zero()
  local unresolvedEntries, _, unresolvedReport = Docs.loadDir(UNRESOLVED_DIR)
  A.same(unresolvedReport.unresolved, { "Constants.Nope.X" })
  A.eq(docNamed(unresolvedEntries, "Nope").doc.Missing, 0)
  A.eq(docNamed(unresolvedEntries, "Nope").doc.Found, 1)
end

local function test_resolved_docs_report_no_unresolved_references()
  A.same(report.unresolved, {})
end

local function test_missing_dir_errors()
  A.errors(function()
    Docs.loadDir(TEST_DIR .. "/../fixtures/no_such_dir")
  end, "not a directory")
end

return function()
  test_load_dir_loads_only_lua_files()
  test_load_dir_reports_no_errors_for_valid_docs()
  test_entry_names_its_source_file()
  test_captured_doc_keeps_its_shape()
  test_enum_reference_resolves_to_enum_value()
  test_enum_arithmetic_resolves()
  test_constant_reference_resolves()
  test_constant_chained_through_other_constants_resolves()
  test_enum_typed_string_constant_resolves_to_enum_value()
  test_cstring_constant_stays_a_string()
  test_enum_meta_resolves_to_num_values()
  test_report_counts_passes_until_settled()
  test_broken_file_is_reported_with_its_filename()
  test_unsettled_values_are_reported_after_max_passes()
  test_unresolved_reference_is_reported_and_loads_as_zero()
  test_resolved_docs_report_no_unresolved_references()
  test_missing_dir_errors()
end
