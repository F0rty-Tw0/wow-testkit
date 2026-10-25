-- Assets.locate: finds the addon or client-extract file behind a snapshot asset; the cases are shared with preview_assets.py.
local A = require("assert")
local Assets = require("session_assets")
local ClientH = require("tests.helpers.client")
local Json = require("json")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."

local function readCases()
  return Json.decode(assert(fs.readFile(TEST_DIR .. "/fixtures/session_assets/cases.json")))
end

local function emptyFiles(names)
  local files = {}
  for _, name in ipairs(names) do
    files[name] = ""
  end
  return files
end

-- The addon tree under <root>/addons and the extract (plus atlas.lua) under <root>; returns the addon roots and the extract.
local function build(cases)
  local root = Tmp.dir("assets")
  local addons = root .. "/addons"
  for _, name in ipairs(cases.addonFiles) do
    fs.mkdirp(addons .. "/" .. name:match("^(.*)/[^/]*$"))
    fs.writeFile(addons .. "/" .. name, "")
  end
  local files = emptyFiles(cases.extractFiles)
  files["atlas.lua"] = cases.atlasLua
  return { locdemo = addons .. "/LocDemo" }, ClientH.extract(root, "retail", "1", files)
end

local function expected(case)
  return case.expect ~= Json.null and case.expect or nil
end

local function caseNamed(cases, name)
  for _, case in ipairs(cases.cases) do
    if case.name == name then
      return case
    end
  end
  error("no case " .. name)
end

local function test_locate_matches_every_shared_case()
  local cases = readCases()
  local roots, extract = build(cases)
  for _, case in ipairs(cases.cases) do
    A.same(Assets.locate(roots, extract, case.asset), expected(case), case.name)
  end
end

local function test_no_extract_means_no_extract_hits()
  local cases = readCases()
  local roots = build(cases)
  A.eq(Assets.locate(roots, nil, caseNamed(cases, "file_id").asset), nil)
  A.eq(Assets.locate(roots, nil, caseNamed(cases, "font_ttf").asset), nil)
  A.eq(Assets.locate(roots, nil, caseNamed(cases, "atlas").asset), nil)
  A.same(Assets.locate(roots, nil, caseNamed(cases, "mixed_case_no_extension").asset), { source = "addon", path = "Art/Icon.PNG" })
end

local function test_a_missing_root_or_folder_is_a_miss()
  local cases = readCases()
  local _, extract = build(cases)
  local asset = caseNamed(cases, "mixed_case_no_extension").asset
  A.eq(Assets.locate({ locdemo = Tmp.dir("assets") .. "/gone" }, extract, asset), nil)
  A.eq(Assets.locate({}, extract, asset), nil)
end

local function test_a_file_where_a_folder_is_wanted_is_a_miss()
  local cases = readCases()
  local roots, extract = build(cases)
  A.eq(Assets.locate(roots, extract, { kind = "path", path = "Interface/AddOns/LocDemo/Art/Icon.PNG/x" }), nil)
end

local function test_a_malformed_asset_is_a_miss()
  local roots, extract = build(readCases())
  A.eq(Assets.locate(roots, extract, { kind = "path" }), nil)
  A.eq(Assets.locate(roots, extract, { kind = "fileID", fileID = 1.5 }), nil)
  A.eq(Assets.locate(roots, extract, { kind = "atlas", atlas = 7 }), nil)
  A.eq(Assets.locate(roots, extract, { kind = "sound" }), nil)
  A.eq(Assets.locate(roots, extract, nil), nil)
end

return function()
  test_locate_matches_every_shared_case()
  test_no_extract_means_no_extract_hits()
  test_a_missing_root_or_folder_is_a_miss()
  test_a_file_where_a_folder_is_wanted_is_a_miss()
  test_a_malformed_asset_is_a_miss()
end
