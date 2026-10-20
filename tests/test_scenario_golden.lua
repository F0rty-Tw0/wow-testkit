-- Scenario snapshots checked against goldens: mismatch, update, menu values, a missing target, a skipped flavor,
-- golden mode.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")
local Scenario = require("scenario")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local ADDONS_DIR = TEST_DIR .. "/fixtures/addons"
local GOLDEN_MODE_SCENARIO = TEST_DIR .. "/fixtures/scenarios/scn_golden_mode.lua"
local HOVER = { addon = "Hover", root = ADDONS_DIR .. "/Hover" }
local RETAIL_ONLY = { addon = "RetailOnly", root = ADDONS_DIR .. "/RetailOnly" }
local BOB = { name = "Bob", isPlayer = true, classFile = "MAGE", className = "Mage", raceName = "Orc", level = 80 }

local function tempRoot()
  return Tmp.dir("scenario")
end

-- Runs fn(s) on retail with snapshots checked against goldens under root (scenario "hover"); update writes them.
local function goldenRun(root, fn, update)
  local opts = { addon = HOVER.addon, root = HOVER.root, golden = { root = root, scenario = "hover", update = update } }
  return Scenario.matrix({ "retail" }, fn, opts).retail
end

local function test_snapshot_mismatch_fails_the_report_without_throwing()
  local root = tempRoot()
  fs.mkdirp(root .. "/tests/scenarios/golden/hover")
  fs.writeFile(root .. "/tests/scenarios/golden/hover/tooltip.retail.txt", "L: [ffffff]Nope\n")
  local reached = false
  local report = goldenRun(root, function(s)
    s:login()
    s:unit("mouseover", BOB)
    s:hover("mouseover")
    s:snapshot("tooltip", _G.GameTooltip)
    reached = true
  end)
  A.eq(reached, true)
  A.eq(report.status, "fail")
  A.contains(tostring(report.errors[1].message), "line 1")
end

local function test_snapshot_writes_the_golden_with_a_note_on_update()
  local root = tempRoot()
  local report = goldenRun(root, function(s)
    s:snapshot("frame", _G.CreateFrame("Frame", "SnapFrame", _G.UIParent))
  end, true)
  A.eq(report.status, "pass")
  A.contains(report.notes, "golden written: hover/frame.retail.txt")
  A.eq(fs.readFile(root .. "/tests/scenarios/golden/hover/frame.retail.txt"), 'Frame "SnapFrame" 0x0\n')
end

local function test_snapshot_reads_are_not_counted_as_unscripted()
  local report = goldenRun(tempRoot(), function(s)
    local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    frame:CreateTexture()
    s:snapshot("frame", frame)
  end, true)
  A.same(report.unscripted, {})
end

local function test_undeclared_flavor_skips_the_rest_of_the_run_and_writes_no_golden()
  local root = tempRoot()
  local opts = { addon = RETAIL_ONLY.addon, root = RETAIL_ONLY.root, golden = { root = root, scenario = "skip", update = true } }
  local results = Scenario.matrix({ "retail", "vanilla" }, function(s)
    s:login()
    assert(s.ns.ok, "addon state not set")
    s:snapshot("t", _G.GameTooltip)
  end, opts)
  A.eq(results.retail.status, "pass")
  A.eq(results.vanilla.status, "skipped")
  A.eq(results.vanilla.reason, "not declared")
  A.same(results.vanilla.errors, {})
  A.truthy(fs.exists(root .. "/tests/scenarios/golden/skip/t.retail.txt"), "retail golden written")
  A.eq(fs.exists(root .. "/tests/scenarios/golden/skip/t.vanilla.txt"), false)
end

local function test_snapshot_checks_a_menu_value_against_its_golden()
  local root = tempRoot()
  local report = goldenRun(root, function(s)
    s:snapshot("menu", { kind = "menu", levels = { { entries = { { kind = "button", text = "Open", enabled = true } } } } })
  end, true)
  A.eq(report.status, "pass")
  A.eq(fs.readFile(root .. "/tests/scenarios/golden/hover/menu.retail.txt"), "[ffffff]Open\n")
end

-- s:menu() is nil when no menu is open, so s:snapshot(name, s:menu()) must say so at the scenario's line.
local function test_snapshot_without_a_target_throws_at_the_caller()
  local message
  goldenRun(tempRoot(), function(s)
    message = A.errors(function()
      s:snapshot("menu", nil)
    end, "s:snapshot: no target to snapshot (got nil)")
  end)
  A.contains(message, "test_scenario_golden.lua:")
end

local function test_run_file_turns_on_golden_mode()
  local opts = { addon = HOVER.addon, root = HOVER.root, flavors = { "retail" } }
  A.eq(Scenario.runFile(GOLDEN_MODE_SCENARIO, opts).results.retail.status, "pass")
end

return function()
  test_snapshot_mismatch_fails_the_report_without_throwing()
  test_snapshot_writes_the_golden_with_a_note_on_update()
  test_snapshot_reads_are_not_counted_as_unscripted()
  test_snapshot_checks_a_menu_value_against_its_golden()
  test_snapshot_without_a_target_throws_at_the_caller()
  test_run_file_turns_on_golden_mode()
  test_undeclared_flavor_skips_the_rest_of_the_run_and_writes_no_golden()
end
