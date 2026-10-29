-- Dependency-ordered addon loading: the load order from the TOC directives, a missing dependency or a cycle blocking an
-- addon, Blizzard_ dependencies counting as present, and a scenario login loading dependencies first.
local TEST_BUDGET = 100000

local A = require("assert")
local AddonDeps = require("addon_deps")
local Flavors = require("tools.flavors")
local Scenario = require("scenario")
local Smoke = require("smoke")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local BASE = "HandyNotes = { dbs = {} }\nfunction HandyNotes:RegisterPluginDB(n, db) self.dbs[n] = db end\n"
  .. 'LOADED = {}\nlocal f = CreateFrame("Frame")\nf:RegisterEvent("ADDON_LOADED")\n'
  .. 'f:SetScript("OnEvent", function(_, _, n) LOADED[#LOADED + 1] = n end)\n'

local HEADER = "## Interface: 120100\n## Interface-Mists: 50504\n## Interface-Vanilla: 11509\n## Interface-TBC: 20506\n"
  .. "## Interface-Forever: 16001\n"

-- Writes <dir>/<name>/<name>.toc (declared on every flavor, then header, then the file line) and <name>.lua.
local function addon(dir, name, header, lua)
  fs.mkdirp(dir .. "/" .. name)
  fs.writeFile(dir .. "/" .. name .. "/" .. name .. ".toc", HEADER .. header .. name .. ".lua\n")
  fs.writeFile(dir .. "/" .. name .. "/" .. name .. ".lua", lua)
end

local function names(entries)
  local list = {}
  for i, entry in ipairs(entries) do
    list[i] = entry.name
  end
  return list
end

local function orderOf(dir, name)
  return AddonDeps.order({ name = name, root = dir .. "/" .. name, flavor = "retail" })
end

-- source: confirmed (row G16) Dependencies, RequiredDeps and Dep* addons load first.
local function test_order_puts_dependencies_first()
  local dir = Tmp.dir("deps")
  addon(dir, "A", "", "")
  addon(dir, "B", "## Dependencies: A\n", "")
  addon(dir, "C", "## RequiredDeps: B\n", "")
  A.same(names(orderOf(dir, "C")), { "A", "B", "C" })
end

-- source: assumed (row G16) the order among unrelated addons: required first, then optional.
local function test_required_then_optional_and_absent_optional_ignored_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "R", "", "")
  addon(dir, "O", "", "")
  addon(dir, "P", "## OptionalDeps: O, Gone\n## RequiredDeps: R\n", "")
  A.same(names(orderOf(dir, "P")), { "R", "O", "P" })
end

local function test_a_shared_dependency_loads_once()
  local dir = Tmp.dir("deps")
  addon(dir, "Base", "", "")
  addon(dir, "L", "## Dependencies: Base\n", "")
  addon(dir, "R", "## Dependencies: Base\n", "")
  addon(dir, "Top", "## Dependencies: L, R\n", "")
  A.same(names(orderOf(dir, "Top")), { "Base", "L", "R", "Top" })
end

-- source: assumed (row G16) a missing required dependency stops the load.
local function test_missing_required_dependency_blocks_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "P", "## Dependencies: Nope\n", "")
  local entries, reason = orderOf(dir, "P")
  A.eq(entries, nil)
  A.eq(reason, "missing dependency: Nope")
end

-- source: assumed (row G16) a cycle blocks every addon in it.
local function test_cycle_blocks_both_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "X", "## Dependencies: Y\n", "")
  addon(dir, "Y", "## Dependencies: X\n", "")
  local entries, reason = orderOf(dir, "X")
  A.eq(entries, nil)
  A.contains(reason, "dependency cycle: X -> Y -> X")
  local _, other = orderOf(dir, "Y")
  A.contains(other, "dependency cycle: Y -> X -> Y")
end

-- source: assumed (row G16) only a cycle of required dependencies blocks; an optional edge in it is passed over.
local function test_a_cycle_through_an_optional_dependency_does_not_block_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "A", "## Dependencies: B\n", "")
  addon(dir, "B", "## OptionalDeps: A\n", "")
  A.same(names(orderOf(dir, "A")), { "B", "A" })
end

-- The order must not depend on which dependency is listed first.
local function test_the_listing_order_does_not_change_whether_an_addon_loads()
  local dir = Tmp.dir("deps")
  addon(dir, "A", "## OptionalDeps: B\n", "")
  addon(dir, "B", "## Dependencies: A\n", "")
  addon(dir, "R1", "## Dependencies: A, B\n", "")
  addon(dir, "R2", "## Dependencies: B, A\n", "")
  A.same({ names(orderOf(dir, "R1")), names(orderOf(dir, "R2")) }, { { "A", "B", "R1" }, { "A", "B", "R2" } })
end

-- source: assumed (row G16) Blizzard_* dependencies count as present and are not listed.
local function test_blizzard_dependency_counts_as_present_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "P", "## Dependencies: Blizzard_Calendar\n", "")
  A.same(names(orderOf(dir, "P")), { "P" })
end

local function test_addons_dir_defaults_to_the_parent_of_the_root()
  A.eq(AddonDeps.addonsDirOf("a/b/C"), "a/b")
  A.eq(AddonDeps.addonsDirOf("a\\b\\C\\"), "a/b")
  A.eq(AddonDeps.addonsDirOf("."), "..")
  A.eq(AddonDeps.addonsDirOf("C"), ".")
end

local function test_an_explicit_addons_dir_finds_dependencies_elsewhere()
  local dir, other = Tmp.dir("deps"), Tmp.dir("deps")
  addon(dir, "Lib", "", "")
  addon(other, "P", "## Dependencies: Lib\n", "")
  local entries = AddonDeps.order({ name = "P", root = other .. "/P", addonsDir = dir, flavor = "retail" })
  A.same(names(entries), { "Lib", "P" })
end

local function test_login_takes_dependencies_from_the_addons_dir_option()
  local dir, other = Tmp.dir("deps"), Tmp.dir("deps")
  addon(dir, "Lib", "", "")
  addon(other, "P", "## Dependencies: Lib\n", "")
  local deps
  local results = Scenario.matrix({ "retail" }, function(s)
    s:login()
    deps = names(s.deps)
    A.eq(s.w.mock.addonsDir, dir)
  end, { addon = "P", root = other .. "/P", addonsDir = dir })
  A.eq(results.retail.status, "pass")
  A.same(deps, { "Lib" })
end

-- source: confirmed (row G16) a plugin that lists its base as a dependency loads after it, so the base's table exists.
local function test_handynotes_plugin_loads_after_its_base()
  local dir = Tmp.dir("deps")
  addon(dir, "HandyNotes", "", BASE)
  for i = 1, 7 do
    addon(dir, "HandyNotes_P" .. i, "## RequiredDeps: HandyNotes\n", 'HandyNotes:RegisterPluginDB("P' .. i .. '", {})')
  end
  for i = 1, 7 do
    local result = Smoke.runAddon(dir .. "/HandyNotes_P" .. i, Flavors.list, TEST_BUDGET)
    for _, flavor in ipairs(Flavors.list) do
      A.eq(result.results[flavor].status, "pass", i .. " " .. flavor)
    end
  end
end

-- source: confirmed (row G16) ADDON_LOADED fires for each addon after its files, so a dependency's comes first.
local function test_dependency_fires_addon_loaded_first()
  local dir = Tmp.dir("deps")
  addon(dir, "HandyNotes", "", BASE)
  addon(dir, "HandyNotes_P1", "## RequiredDeps: HandyNotes\n", "")
  local seen
  local results = Scenario.matrix({ "retail" }, function(s)
    s:login()
    seen = { unpack(_G.LOADED) }
  end, { addon = "HandyNotes_P1", root = dir .. "/HandyNotes_P1" })
  A.eq(results.retail.status, "pass")
  A.same(seen, { "HandyNotes", "HandyNotes_P1" })
end

local function test_login_lists_dependencies_and_notes_them()
  local dir = Tmp.dir("deps")
  addon(dir, "Lib", "", "")
  addon(dir, "P", "## Dependencies: Lib\n", "")
  local deps
  local results = Scenario.matrix({ "retail" }, function(s)
    s:login()
    deps = names(s.deps)
    A.eq(s.info.status, "loaded")
  end, { addon = "P", root = dir .. "/P" })
  A.same(deps, { "Lib" })
  A.contains(results.retail.notes[1], "loaded dependency Lib")
end

-- source: assumed (row G16) a dependency that does not load on the flavor stops the addon on it.
local function test_dependency_skipped_on_the_flavor_skips_the_dependent_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "OnlyRetail", "", "")
  fs.writeFile(dir .. "/OnlyRetail/OnlyRetail.toc", "## Interface: 120100\nOnlyRetail.lua\n")
  addon(dir, "NeedsIt", "## Dependencies: OnlyRetail\n", "")
  local results = Scenario.matrix({ "retail", "vanilla" }, function(s)
    s:login()
  end, { addon = "NeedsIt", root = dir .. "/NeedsIt" })
  A.same({ results.retail.status, results.vanilla.status }, { "pass", "skipped" })
  A.contains(results.vanilla.reason, "dependency OnlyRetail not loadable")
end

-- source: assumed (row G16) any required dependency that does not load stops the addon, not only the first listed.
local function test_a_skipped_second_required_dependency_skips_the_dependent_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "Lib", "", "")
  addon(dir, "OnlyRetail", "", "")
  fs.writeFile(dir .. "/OnlyRetail/OnlyRetail.toc", "## Interface: 120100\nOnlyRetail.lua\n")
  addon(dir, "NeedsBoth", "## Dependencies: Lib, OnlyRetail\n", "")
  local results = Scenario.matrix({ "vanilla" }, function(s)
    s:login()
  end, { addon = "NeedsBoth", root = dir .. "/NeedsBoth" })
  A.eq(results.vanilla.status, "skipped")
  A.contains(results.vanilla.reason, "dependency OnlyRetail not loadable")
end

-- source: confirmed (row G16) optional dependencies load first "when present"; assumed the client still loads the addon
-- when one is installed but cannot load on the flavor.
local function test_optional_dependency_not_loadable_on_the_flavor_is_passed_over_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "OnlyRetail", "", "")
  fs.writeFile(dir .. "/OnlyRetail/OnlyRetail.toc", "## Interface: 120100\nOnlyRetail.lua\n")
  addon(dir, "Main", "## OptionalDeps: OnlyRetail\n", "MAIN_RAN = true")
  local ran
  local results = Scenario.matrix({ "vanilla" }, function(s)
    s:login()
    ran = rawget(_G, "MAIN_RAN")
    A.eq(s.info.status, "loaded")
  end, { addon = "Main", root = dir .. "/Main" })
  A.eq(results.vanilla.status, "pass", tostring(results.vanilla.reason))
  A.eq(ran, true)
end

-- source: assumed (row G16) an optional dependency that cannot load because its own required dependency is absent is
-- passed over, and the addon still loads.
local function test_optional_dependency_missing_its_own_dependency_is_passed_over_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "O", "## Dependencies: Gone\n", "")
  addon(dir, "Main", "## OptionalDeps: O\n", "")
  A.same(names(orderOf(dir, "Main")), { "Main" })
end

-- source: assumed (row G16) an optional dependency whose own required dependency does not load on the flavor does not
-- load either; the addon still loads.
local function test_optional_dependency_whose_dependency_is_skipped_does_not_load_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "OnlyRetail", "", "")
  fs.writeFile(dir .. "/OnlyRetail/OnlyRetail.toc", "## Interface: 120100\nOnlyRetail.lua\n")
  addon(dir, "O", "## Dependencies: OnlyRetail\n", "O_RAN = true")
  addon(dir, "Main", "## OptionalDeps: O\n", "MAIN_RAN = true")
  local seen
  local results = Scenario.matrix({ "vanilla" }, function(s)
    s:login()
    seen = { rawget(_G, "O_RAN"), rawget(_G, "MAIN_RAN") }
  end, { addon = "Main", root = dir .. "/Main" })
  A.eq(results.vanilla.status, "pass", tostring(results.vanilla.reason))
  A.same(seen, { nil, true })
end

-- source: assumed (row G16) a required dependency the mock holds as loaded is satisfied without a folder.
local function test_a_required_dependency_mocked_loaded_needs_no_folder_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "Main", "## Dependencies: Lib\n", "MAIN_RAN = true")
  local ran
  local results = Scenario.matrix({ "retail" }, function(s)
    s:mock({ addons = { Lib = { loaded = true } } })
    s:login()
    ran = rawget(_G, "MAIN_RAN")
  end, { addon = "Main", root = dir .. "/Main" })
  A.eq(results.retail.status, "pass", tostring(results.retail.reason))
  A.eq(ran, true)
end

-- source: assumed (row G16) a dependency the mock holds as loaded is not walked, even with a folder: its own
-- dependencies were met when it loaded, so one missing from the addons dir does not skip the addon.
local function test_a_dependency_mocked_loaded_is_not_walked_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "Lib", "## Dependencies: Gone\n", "LIB_RAN = true")
  addon(dir, "Main", "## Dependencies: Lib\n", "MAIN_RAN = true")
  local ran
  local results = Scenario.matrix({ "retail" }, function(s)
    s:mock({ addons = { Lib = { loaded = true } } })
    s:login()
    ran = { rawget(_G, "LIB_RAN"), rawget(_G, "MAIN_RAN") }
  end, { addon = "Main", root = dir .. "/Main" })
  A.eq(results.retail.status, "pass", tostring(results.retail.reason))
  A.same(ran, { nil, true })
end

-- source: assumed (row G16) a missing required dependency stops the login as a skip with the reason.
local function test_login_with_a_missing_dependency_is_skipped_assumed()
  local dir = Tmp.dir("deps")
  addon(dir, "P", "## Dependencies: Nope\n", "LOADED_P = true")
  local results = Scenario.matrix({ "retail" }, function(s)
    s:login()
  end, { addon = "P", root = dir .. "/P" })
  A.eq(results.retail.status, "skipped")
  A.eq(results.retail.reason, "missing dependency: Nope")
  A.eq(rawget(_G, "LOADED_P"), nil)
end

local function test_a_dependency_already_loaded_does_not_load_again()
  local dir = Tmp.dir("deps")
  addon(dir, "Lib", "", "LIB_RUNS = (LIB_RUNS or 0) + 1")
  addon(dir, "P", "## Dependencies: Lib\n", "")
  local runs
  Scenario.matrix({ "retail" }, function(s)
    s:mock({ addons = { Lib = { loaded = true } } })
    s:login()
    runs = rawget(_G, "LIB_RUNS")
    A.same(names(s.deps), {})
  end, { addon = "P", root = dir .. "/P" })
  A.eq(runs, nil)
end

return function()
  test_order_puts_dependencies_first()
  test_required_then_optional_and_absent_optional_ignored_assumed()
  test_a_shared_dependency_loads_once()
  test_missing_required_dependency_blocks_assumed()
  test_cycle_blocks_both_assumed()
  test_a_cycle_through_an_optional_dependency_does_not_block_assumed()
  test_the_listing_order_does_not_change_whether_an_addon_loads()
  test_blizzard_dependency_counts_as_present_assumed()
  test_addons_dir_defaults_to_the_parent_of_the_root()
  test_an_explicit_addons_dir_finds_dependencies_elsewhere()
  test_login_takes_dependencies_from_the_addons_dir_option()
  test_handynotes_plugin_loads_after_its_base()
  test_dependency_fires_addon_loaded_first()
  test_login_lists_dependencies_and_notes_them()
  test_dependency_skipped_on_the_flavor_skips_the_dependent_assumed()
  test_a_skipped_second_required_dependency_skips_the_dependent_assumed()
  test_optional_dependency_not_loadable_on_the_flavor_is_passed_over_assumed()
  test_optional_dependency_missing_its_own_dependency_is_passed_over_assumed()
  test_optional_dependency_whose_dependency_is_skipped_does_not_load_assumed()
  test_a_required_dependency_mocked_loaded_needs_no_folder_assumed()
  test_a_dependency_mocked_loaded_is_not_walked_assumed()
  test_login_with_a_missing_dependency_is_skipped_assumed()
  test_a_dependency_already_loaded_does_not_load_again()
end
