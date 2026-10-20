-- Scenarios: an addon logged in on a flavor, driven by hover/fire/advance, reported per flavor in a matrix.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")
local Flavors = require("tools.flavors")
local Scenario = require("scenario")
local Rec = require("tests.helpers.input")
local World = require("world")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local ADDONS_DIR = TEST_DIR .. "/fixtures/addons"
local BASIC_SCENARIO = TEST_DIR .. "/fixtures/scenarios/scn_basic.lua"
local GOLDEN_MODE_SCENARIO = TEST_DIR .. "/fixtures/scenarios/scn_golden_mode.lua"
local HOVER = { addon = "Hover", root = ADDONS_DIR .. "/Hover" }
local POLY = { addon = "Poly", root = ADDONS_DIR .. "/Poly" }
local RETAIL_ONLY = { addon = "RetailOnly", root = ADDONS_DIR .. "/RetailOnly" }
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

local function test_run_continues_after_a_handler_error()
  local opts = { addon = HOVER.addon, root = HOVER.root, saved = { HoverDB = { boom = true } } }
  local texts
  local report = Scenario.matrix({ "retail" }, function(s)
    s:login()
    s:unit("mouseover", BOB)
    s:hover("mouseover")
    texts = tooltipTexts()
  end, opts).retail
  A.eq(report.status, "fail")
  A.contains(tostring(report.errors[1].message), "boom")
  A.contains(texts, "Hi Bob")
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

local function copyOf(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

local function test_addon_library_writes_do_not_leak_across_flavors()
  local tableBefore, stringBefore = copyOf(table), copyOf(string)
  local hadPoly = {}
  Scenario.matrix({ "retail", "mists" }, function(s)
    s:login()
    hadPoly[s.flavor] = s.ns.hadPoly
  end, POLY)
  A.same(hadPoly, { retail = false, mists = false })
  A.same(copyOf(table), tableBefore, "table")
  A.same(copyOf(string), stringBefore, "string")
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

local function test_thrown_run_error_keeps_its_message_after_an_addon_sets_debug()
  local root = Tmp.dir("scenario") .. "/DebugSet"
  fs.mkdirp(root)
  fs.writeFile(root .. "/DebugSet.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", "debug = true\n")
  local report = Scenario.matrix({ "retail" }, function(s)
    s:login()
    error("scenario exploded")
  end, { addon = "DebugSet", root = root }).retail
  A.contains(tostring(report.errors[1].message), "scenario exploded")
  A.contains(tostring(report.errors[1].traceback), "stack traceback")
end

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
  A.contains(message, "test_scenario.lua:")
end

local function test_run_file_turns_on_golden_mode()
  local opts = { addon = HOVER.addon, root = HOVER.root, flavors = { "retail" } }
  A.eq(Scenario.runFile(GOLDEN_MODE_SCENARIO, opts).results.retail.status, "pass")
end

-- (I10) over the world: WorldFrame only when its motion is enabled, else no focus.
local function test_hover_leaves_no_focus_when_world_frame_motion_is_off() -- (I10)
  withHover("retail", function(s)
    local b = _G.CreateFrame("Button", nil, _G.UIParent)
    local log = Rec.record(b, { "OnLeave" })
    s:enter(b)
    s:unit("mouseover", BOB)
    s:hover("mouseover")
    A.same(log, { { "OnLeave", true } })
    A.eq(s.w.input.mouseFocus, nil)
    A.same(_G.GetMouseFoci(), {})
  end)
end

local function test_hover_focuses_the_world_frame_when_its_motion_is_on() -- (I10)
  withHover("retail", function(s)
    s.w:run("blizzard", function()
      _G.WorldFrame:SetMouseMotionEnabled(true)
    end)
    s:unit("mouseover", BOB)
    s:hover("mouseover")
    A.eq(s.w.input.mouseFocus, _G.WorldFrame)
  end)
end

local function test_report_appends_world_notes()
  withHover("retail", function(s)
    s.w.notes[#s.w.notes + 1] = "from a menu fake"
    A.contains(s:report().notes, "from a menu fake")
  end)
end

local function test_report_works_when_the_world_has_no_notes()
  withHover("retail", function(s)
    s.w.notes = nil
    A.same(s:report().notes, {})
  end)
end

return function()
  test_hover_runs_the_unit_post_call_on_retail()
  test_hover_runs_the_tooltip_set_unit_hook_on_vanilla()
  test_login_fires_player_login_once()
  test_hover_leaves_no_focus_when_world_frame_motion_is_off()
  test_hover_focuses_the_world_frame_when_its_motion_is_on()
  test_report_appends_world_notes()
  test_report_works_when_the_world_has_no_notes()
  test_login_error_fails_the_report_with_its_addon_source()
  test_run_continues_after_a_handler_error()
  test_run_file_runs_every_flavor_by_default()
  test_run_file_reports_an_undeclared_flavor_as_skipped()
  test_matrix_destroys_every_world()
  test_addon_library_writes_do_not_leak_across_flavors()
  test_thrown_run_error_fails_only_that_flavor()
  test_thrown_run_error_keeps_its_message_after_an_addon_sets_debug()
  test_snapshot_mismatch_fails_the_report_without_throwing()
  test_snapshot_writes_the_golden_with_a_note_on_update()
  test_snapshot_reads_are_not_counted_as_unscripted()
  test_snapshot_checks_a_menu_value_against_its_golden()
  test_snapshot_without_a_target_throws_at_the_caller()
  test_run_file_turns_on_golden_mode()
  test_undeclared_flavor_skips_the_rest_of_the_run_and_writes_no_golden()
end
