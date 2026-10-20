local A = require("assert")
local Docs = require("tools.docs")
local Generate = require("tools.generate")
local GenerateIo = require("tools.generate_io")
local Manifest = require("manifest")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local DOCS_DIR = TEST_DIR .. "/../fixtures/docs"
local KETHO_DIR = TEST_DIR .. "/../fixtures/ketho"
local UNRESOLVED_DIR = TEST_DIR .. "/../fixtures/docs_unresolved"
local UNSETTLED_DIR = TEST_DIR .. "/../fixtures/docs_unsettled"
local META = { flavor = "retail", branch = "live", version = "12.1.0.69933", mirrorCommit = "abc123" }

math.randomseed(os.time())

local function tempDir()
  local base = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/")
  return base .. "/wow-testkit-gen-" .. os.time() .. "-" .. math.random(1, 1000000)
end

local ketho = GenerateIo.loadKetho(KETHO_DIR)
local result = Generate.build(Docs.loadDir(DOCS_DIR), ketho, META)

local function test_load_ketho_takes_each_returned_table()
  A.same(ketho.GlobalAPI[2], { "abs", "string.format" })
  A.same(ketho.Frames[2], { "MacroFrame" })
  A.same(ketho.Events.System, { "PLAYER_LOGIN" })
  A.same(ketho.WidgetAPI.Frame.inherits, { "Object" })
end

local function test_write_split_lists_written_files_in_the_index()
  local root = tempDir()
  GenerateIo.writeSplit(root, result)
  local index = assert(loadfile(root .. "/api/retail/init.lua"))()
  local expected = {
    flavor = "retail",
    branch = "live",
    version = "12.1.0.69933",
    mirrorCommit = "abc123",
    files = { "Enum", "SecureSystem", "SimpleFrameAPI", "Unit" },
  }
  A.same(index, expected)
end

local function test_write_split_removes_stale_files()
  local root = tempDir()
  fs.mkdirp(root .. "/api/retail")
  fs.writeFile(root .. "/api/retail/Gone.lua", "return {}\n")
  GenerateIo.writeSplit(root, result)
  A.eq(fs.exists(root .. "/api/retail/Gone.lua"), false)
end

local function test_write_split_returns_each_file_size()
  local root = tempDir()
  local sizes = GenerateIo.writeSplit(root, result)
  A.eq(sizes["api/retail/Unit.lua"], #fs.readFile(root .. "/api/retail/Unit.lua"))
  A.truthy(sizes["api/retail/globals.lua"], "globals.lua is sized")
end

local function test_written_split_manifest_loads_back_whole()
  local root = tempDir()
  GenerateIo.writeSplit(root, result)
  local manifest, globals = Manifest.load("retail", { root = root })
  A.same(manifest.functions, result.manifest.functions)
  A.same(manifest.widgets, result.manifest.widgets)
  A.same(globals, result.globals)
end

local function test_update_versions_keeps_other_flavors()
  local root = tempDir()
  fs.mkdirp(root .. "/api")
  fs.writeFile(root .. "/api/versions.lua", 'return { tbc = { version = "2.5.6.1", mirrorCommit = "t" } }\n')
  GenerateIo.updateVersions(root, META)
  local versions = assert(loadfile(root .. "/api/versions.lua"))()
  A.same(versions, {
    tbc = { version = "2.5.6.1", mirrorCommit = "t" },
    retail = { version = "12.1.0.69933", mirrorCommit = "abc123" },
  })
end

local function test_update_versions_creates_missing_file()
  local root = tempDir()
  GenerateIo.updateVersions(root, META)
  local versions = assert(loadfile(root .. "/api/versions.lua"))()
  A.same(versions, { retail = { version = "12.1.0.69933", mirrorCommit = "abc123" } })
end

local function test_docs_report_lists_unresolved_references()
  local _, _, report = Docs.loadDir(UNRESOLVED_DIR)
  A.contains(GenerateIo.docsReportLines(report), "  Constants.Nope.X")
end

local function test_unresolved_references_alone_do_not_fail_the_run()
  local _, _, report = Docs.loadDir(UNRESOLVED_DIR)
  A.eq(GenerateIo.exitCode({}, report), 0)
end

local function test_unsettled_docs_are_reported_and_fail_the_run()
  local _, _, report = Docs.loadDir(UNSETTLED_DIR)
  local lines = table.concat(GenerateIo.docsReportLines(report), "\n")
  A.contains(lines, "not settled")
  A.eq(GenerateIo.exitCode({}, report), 1)
end

return function()
  test_load_ketho_takes_each_returned_table()
  test_write_split_lists_written_files_in_the_index()
  test_write_split_removes_stale_files()
  test_write_split_returns_each_file_size()
  test_written_split_manifest_loads_back_whole()
  test_update_versions_keeps_other_flavors()
  test_update_versions_creates_missing_file()
  test_docs_report_lists_unresolved_references()
  test_unresolved_references_alone_do_not_fail_the_run()
  test_unsettled_docs_are_reported_and_fail_the_run()
end
