-- Golden files: snapshot text compared to tests/scenarios/golden/<scenario>/<snapshot>.<flavor>.txt under a root.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")
local Golden = require("golden")

local function tempRoot()
  return Tmp.dir("golden")
end

local function goldenPath(root)
  return root .. "/tests/scenarios/golden/hover/tooltip.retail.txt"
end

local function test_missing_golden_is_written_on_update()
  local root = tempRoot()
  A.eq(Golden.check(root, "hover", "tooltip", "retail", "L: a", true), "written")
  A.eq(fs.readFile(goldenPath(root)), "L: a\n")
end

local function test_missing_golden_errors_without_update_and_writes_nothing()
  local root = tempRoot()
  local message = A.errors(function()
    Golden.check(root, "hover", "tooltip", "retail", "L: a", false)
  end, "--update")
  A.contains(message, goldenPath(root))
  A.eq(fs.exists(goldenPath(root)), false)
end

local function test_identical_text_is_ok()
  local root = tempRoot()
  Golden.check(root, "hover", "tooltip", "retail", "L: a", true)
  A.eq(Golden.check(root, "hover", "tooltip", "retail", "L: a", false), "ok")
end

local function test_crlf_golden_matches_lf_text()
  local root = tempRoot()
  Golden.check(root, "hover", "tooltip", "retail", "L: a", true)
  fs.writeFile(goldenPath(root), "L: a\r\n")
  A.eq(Golden.check(root, "hover", "tooltip", "retail", "L: a", false), "ok")
end

local function test_changed_text_errors_with_line_versions_and_path()
  local root = tempRoot()
  Golden.check(root, "hover", "tooltip", "retail", "L: a", true)
  local message = A.errors(function()
    Golden.check(root, "hover", "tooltip", "retail", "L: b", false)
  end, "line 1")
  A.contains(message, '"L: a"')
  A.contains(message, '"L: b"')
  A.contains(message, goldenPath(root))
end

local function test_update_rewrites_a_differing_golden()
  local root = tempRoot()
  Golden.check(root, "hover", "tooltip", "retail", "L: a", true)
  A.eq(Golden.check(root, "hover", "tooltip", "retail", "L: b", true), "written")
  A.eq(fs.readFile(goldenPath(root)), "L: b\n")
end

return function()
  test_missing_golden_is_written_on_update()
  test_missing_golden_errors_without_update_and_writes_nothing()
  test_identical_text_is_ok()
  test_crlf_golden_matches_lf_text()
  test_changed_text_errors_with_line_versions_and_path()
  test_update_rewrites_a_differing_golden()
end
