-- Preview.run lists every error in the snapshot it writes, including the one the scenario itself threw.
local A = require("assert")
local P = require("tests.helpers.preview")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local FIXTURES = TEST_DIR .. "/fixtures/addons"

local function countOf(text, needle)
  local _, count = text:gsub(needle, "")
  return count
end

local function test_scenario_thrown_error_is_listed_in_the_snapshot_and_printed_once()
  P.withExec(nil, function()
    local out = Tmp.dir("previewout")
    local path = P.scenarioFile('s:login(); error("scenario boom", 0)')
    local code, text = P.run({ addonDir = P.tempAddon(P.FRAME_ADDON), out = out, scenario = path })
    local snapshot = assert(fs.readFile(out .. "/snapshot.json"))
    A.eq(code, 1)
    A.eq(countOf(snapshot, '"message": "scenario boom"'), 1)
    A.contains(snapshot, '"traceback"')
    A.eq(countOf(text, "error: scenario boom"), 1)
  end)
end

-- The addon's own load error and the scenario's both reach the snapshot, in the order they happened.
local function test_snapshot_keeps_an_addon_error_before_the_scenario_error()
  P.withExec(nil, function()
    local out = Tmp.dir("previewout")
    local path = P.scenarioFile('s:login(); error("scenario boom", 0)')
    P.run({ addonDir = P.tempAddon(P.FRAME_ADDON .. 'error("addon boom", 0)\n'), out = out, scenario = path })
    local snapshot = assert(fs.readFile(out .. "/snapshot.json"))
    local addon, scenario = snapshot:find("addon boom", 1, true), snapshot:find("scenario boom", 1, true)
    A.truthy(addon and scenario and addon < scenario, "addon error first")
  end)
end

-- A skipped addon is no error: the sentinel passes through, so the run exits 2 and the snapshot lists none.
local function test_skipped_addon_is_not_recorded_as_an_error()
  P.withExec(nil, function()
    local out = Tmp.dir("previewout")
    local code = P.run({ addonDir = FIXTURES .. "/RetailOnly", out = out, flavor = "vanilla" })
    A.eq(code, 2)
    A.contains(assert(fs.readFile(out .. "/snapshot.json")), '"errors": []')
  end)
end

return function()
  test_scenario_thrown_error_is_listed_in_the_snapshot_and_printed_once()
  test_snapshot_keeps_an_addon_error_before_the_scenario_error()
  test_skipped_addon_is_not_recorded_as_an_error()
end
