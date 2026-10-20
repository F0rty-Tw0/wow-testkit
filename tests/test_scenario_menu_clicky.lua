-- Menu steps on the Clicky fixture: dropdown, Menu API and DropdownButton snapshots and picks on every flavor.
-- Split from test_scenario_menu.lua (size).
local A = require("assert")
local Clicky = require("tests.helpers.clicky")
local Flavors = require("tools.flavors")
local Scenario = require("scenario")
local Snapshot = require("snapshot")

local CLICKY_MENU = { addon = "Clicky", root = Clicky.ROOT }
local DROPDOWN_LINES = {
  "== Clicky ==",
  "Open",
  "[x] Show",
  "(o) Mode A",
  "( ) Mode B",
  "---",
  "Locked (disabled)",
  "> More",
}
local DROPDOWN_TEXT = table.concat({
  "== [00ff00]Clicky ==",
  "[ffffff]Open",
  "[x] [ffffff]Show",
  "(o) [ffffff]Mode A",
  "( ) [ffffff]Mode B",
  "---",
  "[ffffff]Locked (disabled)",
  "> [ffffff]More",
}, "\n")

-- Runs steps(s) after login on every flavor; returns the reports and what steps stored in out[flavor].
local function clickyMatrix(steps)
  local out = {}
  local reports = Scenario.matrix(Flavors.list, function(s)
    s:login()
    out[s.flavor] = steps(s)
  end, CLICKY_MENU)
  return reports, out
end

local function test_dropdown_menu_snapshot_lists_every_entry_kind_on_every_flavor()
  local reports, texts = clickyMatrix(function(s)
    s:click("ClickyMenuButton")
    return Snapshot.menu(s:menu())
  end)
  for _, flavor in ipairs(Flavors.list) do
    A.eq(reports[flavor].status, "pass", flavor)
    A.textEq(texts[flavor], DROPDOWN_TEXT)
  end
end

local function test_dropdown_submenu_snapshot_nests_under_its_entry()
  local reports, texts = clickyMatrix(function(s)
    s:click("ClickyMenuButton")
    s:enter(s:menu().levels[1].entries[8].frame)
    return Snapshot.menu(s:menu())
  end)
  for _, flavor in ipairs(Flavors.list) do
    A.eq(reports[flavor].status, "pass", flavor)
    A.textEq(texts[flavor], DROPDOWN_TEXT .. "\n  [ffffff]Nested")
  end
end

local function test_dropdown_pick_runs_func_and_closes_the_menu()
  local reports, picks = clickyMatrix(function(s)
    s:click("ClickyMenuButton")
    s:pick("Open")
    return { picks = s.ns.picks, open = s:menu() }
  end)
  for _, flavor in ipairs(Flavors.list) do
    A.eq(reports[flavor].status, "pass", flavor)
    A.same(picks[flavor].picks, { "Open" })
    A.eq(picks[flavor].open, nil)
  end
end

local function test_dropdown_checkbox_pick_passes_the_checked_value()
  local _, picks = clickyMatrix(function(s)
    s:click("ClickyMenuButton")
    s:pick("Show")
    return s.ns.picks
  end)
  A.same(picks.retail, { "Show:true" })
end

local function test_dropdown_path_pick_clicks_the_nested_entry()
  local _, picks = clickyMatrix(function(s)
    s:click("ClickyMenuButton")
    s:pick({ "More", "Nested" })
    return s.ns.picks
  end)
  A.same(picks.retail, { "Nested" })
end

-- The scenario file stays in the repo; only its goldens go to the temp copy.
local function test_scn_input_dropdown_snapshots_are_written_in_a_temp_copy_on_every_flavor()
  local root = Clicky.clickyCopy()
  local result = Scenario.runFile(Clicky.INPUT_SCENARIO, { addon = "Clicky", root = root, update = true })
  local submenu = {}
  for i, line in ipairs(DROPDOWN_LINES) do
    submenu[i] = line
  end
  submenu[#submenu + 1] = "  Nested"
  for _, flavor in ipairs(Flavors.list) do
    A.eq(result.results[flavor].status, "pass", flavor)
    A.same(result.results[flavor].errors, {})
    A.same(Clicky.goldenLines(root, "dropdown_menu", flavor), DROPDOWN_LINES, flavor)
    A.same(Clicky.goldenLines(root, "dropdown_submenu", flavor), submenu, flavor)
  end
end

local EXPECTED_MENU_API = {
  menu_api = { "== Clicky ==", "Plain", "> More", "[ ] Check", "(o) Radio A", "( ) Radio B", "---", "Off (disabled)" },
  menu_api_submenu = {
    "== Clicky ==",
    "Plain",
    "> More",
    "  Deep",
    "[ ] Check",
    "(o) Radio A",
    "( ) Radio B",
    "---",
    "Off (disabled)",
  },
  menu_api_checked = { "== Clicky ==", "Plain", "> More", "[x] Check", "(o) Radio A", "( ) Radio B", "---", "Off (disabled)" },
  menu_unit = { "---", "== Clicky ==", "Clicky action" },
}

local function test_menu_api_snapshots_match_on_every_flavor()
  local root = Clicky.clickyCopy()
  local run = Scenario.runFile(Clicky.INPUT_SCENARIO, { addon = "Clicky", root = root, update = true })
  for _, flavor in ipairs(Flavors.list) do
    local report = run.results[flavor]
    A.eq(report.status, "pass", flavor .. ": " .. tostring(report.errors[1] and report.errors[1].message))
    A.contains(report.notes, "Blizzard's own entries are not simulated")
    for name, lines in pairs(EXPECTED_MENU_API) do
      A.same(Clicky.goldenLines(root, name, flavor), lines, flavor .. " " .. name)
    end
  end
end

local EXPECTED_DROPDOWN = {
  dropdown = { "== Size ==", "(o) Small", "( ) Large", "---", "[ ] Compact" },
  dropdown_large = { "== Size ==", "( ) Small", "(o) Large", "---", "[ ] Compact" },
}

local function test_dropdown_button_snapshots_match_on_every_flavor()
  local root = Clicky.clickyCopy()
  local run = Scenario.runFile(Clicky.INPUT_SCENARIO, { addon = "Clicky", root = root, update = true })
  for _, flavor in ipairs(Flavors.list) do
    local report = run.results[flavor]
    A.eq(report.status, "pass", flavor .. ": " .. tostring(report.errors[1] and report.errors[1].message))
    for name, lines in pairs(EXPECTED_DROPDOWN) do
      A.same(Clicky.goldenLines(root, name, flavor), lines, flavor .. " " .. name)
    end
  end
end

return function()
  test_dropdown_menu_snapshot_lists_every_entry_kind_on_every_flavor()
  test_dropdown_submenu_snapshot_nests_under_its_entry()
  test_dropdown_pick_runs_func_and_closes_the_menu()
  test_dropdown_checkbox_pick_passes_the_checked_value()
  test_dropdown_path_pick_clicks_the_nested_entry()
  test_scn_input_dropdown_snapshots_are_written_in_a_temp_copy_on_every_flavor()
  test_menu_api_snapshots_match_on_every_flavor()
  test_dropdown_button_snapshots_match_on_every_flavor()
end
