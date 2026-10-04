-- Scenarios: an addon logged in on a flavor, driven by hover/fire/advance, reported per flavor in a matrix.
local A = require("assert")
local fs = require("fs")
local Flavors = require("tools.flavors")
local Scenario = require("scenario")
local World = require("world")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local ADDONS_DIR = TEST_DIR .. "/fixtures/addons"
local BASIC_SCENARIO = TEST_DIR .. "/fixtures/scenarios/scn_basic.lua"
local GOLDEN_MODE_SCENARIO = TEST_DIR .. "/fixtures/scenarios/scn_golden_mode.lua"
local HOVER = { addon = "Hover", root = ADDONS_DIR .. "/Hover" }
local BOB = { name = "Bob", isPlayer = true, classFile = "MAGE", className = "Mage", raceName = "Orc", level = 80 }

-- A Hover scenario on flavor, always destroyed.
local function withHover(flavor, fn)
  local s = Scenario.new({ addon = HOVER.addon, root = HOVER.root, flavor = flavor })
  local ok, err = pcall(fn, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function tooltipTexts()
  local texts = {}
  for i = 1, _G.GameTooltip:NumLines() do
    texts[i] = _G["GameTooltipTextLeft" .. i]:GetText()
  end
  return texts
end

local function hoverBob(flavor)
  local texts
  withHover(flavor, function(s)
    s:login()
    s:unit("mouseover", BOB)
    s:hover("mouseover")
    texts = tooltipTexts()
  end)
  return texts
end

local function test_hover_runs_the_unit_post_call_on_retail()
  A.contains(hoverBob("retail"), "Hi Bob")
end

local function test_hover_runs_the_tooltip_set_unit_hook_on_vanilla()
  A.contains(hoverBob("vanilla"), "Hi Bob")
end

local function test_login_fires_player_login_once()
  withHover("retail", function(s)
    s:login()
    A.eq(s.ns.logins, 1)
  end)
end

local function test_login_error_fails_the_report_with_its_addon_source()
  local opts = { addon = HOVER.addon, root = HOVER.root, saved = { HoverDB = { boom = true } } }
  local report = Scenario.matrix({ "retail" }, function(s)
    s:login()
  end, opts).retail
  A.eq(report.status, "fail")
  A.contains(tostring(report.errors[1].message), "boom")
  A.contains(tostring(report.errors[1].source), "addon:Hover/")
end

local function test_run_file_runs_every_flavor_by_default()
  local result = Scenario.runFile(BASIC_SCENARIO, HOVER)
  A.eq(result.name, "basic")
  for _, flavor in ipairs(Flavors.list) do
    A.eq(result.results[flavor].status, "pass")
  end
end

local function test_run_file_reports_an_undeclared_flavor_as_skipped()
  local result = Scenario.runFile(BASIC_SCENARIO, { addon = "WMStyle", root = ADDONS_DIR .. "/WMStyle" })
  A.eq(result.results.vanilla.status, "skipped")
  A.eq(result.results.vanilla.reason, "not declared")
  A.eq(result.results.retail.status, "pass")
end

local function test_matrix_destroys_every_world()
  Scenario.matrix(Flavors.list, function(s)
    s:login()
  end, HOVER)
  local w = World.new({ flavor = "retail" })
  w:destroy()
end

local function test_thrown_run_error_fails_only_that_flavor()
  local results = Scenario.matrix({ "retail", "vanilla" }, function(s)
    if s.flavor == "retail" then
      error("scenario exploded")
    end
    s:login()
  end, HOVER)
  A.eq(results.retail.status, "fail")
  A.contains(tostring(results.retail.errors[#results.retail.errors].message), "scenario exploded")
  A.eq(results.vanilla.status, "pass")
end

local function tempRoot()
  local base = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/")
  return base .. "/wow-testkit-scenario-" .. os.time() .. "-" .. math.random(1, 1000000)
end

-- Runs fn(s) on retail with snapshots checked against goldens under root (scenario "hover").
local function goldenRun(root, fn)
  local opts = { addon = HOVER.addon, root = HOVER.root, golden = { root = root, scenario = "hover" } }
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

local function test_snapshot_writes_a_missing_golden_with_a_note()
  local root = tempRoot()
  local report = goldenRun(root, function(s)
    s:snapshot("frame", _G.CreateFrame("Frame", "SnapFrame", _G.UIParent))
  end)
  A.eq(report.status, "pass")
  A.contains(report.notes, "golden written: hover/frame.retail.txt")
  A.eq(fs.readFile(root .. "/tests/scenarios/golden/hover/frame.retail.txt"), 'Frame "SnapFrame" 0x0\n')
end

local function test_snapshot_reads_are_not_counted_as_unscripted()
  local report = goldenRun(tempRoot(), function(s)
    local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    frame:CreateTexture()
    s:snapshot("frame", frame)
  end)
  A.same(report.unscripted, {})
end

local function test_run_file_turns_on_golden_mode()
  local opts = { addon = HOVER.addon, root = HOVER.root, flavors = { "retail" } }
  A.eq(Scenario.runFile(GOLDEN_MODE_SCENARIO, opts).results.retail.status, "pass")
end

return function()
  test_hover_runs_the_unit_post_call_on_retail()
  test_hover_runs_the_tooltip_set_unit_hook_on_vanilla()
  test_login_fires_player_login_once()
  test_login_error_fails_the_report_with_its_addon_source()
  test_run_file_runs_every_flavor_by_default()
  test_run_file_reports_an_undeclared_flavor_as_skipped()
  test_matrix_destroys_every_world()
  test_thrown_run_error_fails_only_that_flavor()
  test_snapshot_mismatch_fails_the_report_without_throwing()
  test_snapshot_writes_a_missing_golden_with_a_note()
  test_snapshot_reads_are_not_counted_as_unscripted()
  test_run_file_turns_on_golden_mode()
end
