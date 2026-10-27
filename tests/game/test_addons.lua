-- Addon APIs: loaded state, metadata, installed-addon list and info, load on demand, enable flags, and the
-- ReloadUI, Logout and Quit calls. The installed addons are the folders of the scenario's addons directory.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")
local Scenario = require("scenario")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local HEADER = "## Interface: 120100\n## Interface-Mists: 50504\n## Interface-Vanilla: 11509\n## Interface-TBC: 20506\n"
  .. "## Interface-Forever: 16001\n"
-- Records every ADDON_LOADED name in SEEN; only the first addon to run it registers the frame.
local WATCH = 'if not SEEN then\nSEEN = {}\nlocal f = CreateFrame("Frame")\nf:RegisterEvent("ADDON_LOADED")\n'
  .. 'f:SetScript("OnEvent", function(_, _, n) SEEN[#SEEN + 1] = n end)\nend\n'

local function addon(dir, name, header, lua)
  fs.mkdirp(dir .. "/" .. name)
  fs.writeFile(dir .. "/" .. name .. "/" .. name .. ".toc", HEADER .. header .. name .. ".lua\n")
  fs.writeFile(dir .. "/" .. name .. "/" .. name .. ".lua", lua or "")
end

-- HandyNotes, its plugin P (Title: Plugin) and the unloaded Spare (Notes: spare).
local function corpus()
  local dir = Tmp.dir("addons")
  addon(dir, "HandyNotes", "", WATCH)
  addon(dir, "P", "## Title: Plugin\n## RequiredDeps: HandyNotes\n", "")
  addon(dir, "Spare", "## Notes: spare\n", WATCH)
  return dir
end

-- Logs P in on flavor in a scenario over dir, calls fn(s, w), and fails with the world's first error unless the run
-- passed.
local function withLogin(flavor, dir, fn)
  local results = Scenario.matrix({ flavor }, function(s)
    s:login()
    fn(s, s.w)
  end, { addon = "P", root = dir .. "/P" })
  local report = results[flavor]
  A.eq(report.status, "pass", report.errors[1] and tostring(report.errors[1].message) or report.reason)
  return report
end

-- source: confirmed (row G15) IsAddOnLoaded returns loadedOrLoading, loaded; GetAddOnMetadata is nil for an absent
-- field.
local function test_loaded_state_and_metadata()
  withLogin("retail", corpus(), function()
    A.same({ _G.C_AddOns.IsAddOnLoaded("HandyNotes") }, { true, true })
    A.same({ _G.C_AddOns.IsAddOnLoaded("P") }, { true, true })
    A.same({ _G.C_AddOns.IsAddOnLoaded("Spare") }, { false, false })
    A.eq(_G.C_AddOns.GetAddOnMetadata("P", "Title"), "Plugin")
    A.eq(_G.C_AddOns.GetAddOnMetadata("P", "Nope"), nil)
  end)
end

-- source: confirmed (row G15) GetAddOnInfo returns name, title, notes, loadable, reason, security: six values, no
-- newVersion; assumed (row G15) the title is the folder name when the TOC has none, and security is INSECURE.
local function test_counts_and_info_list_installed_addons_assumed()
  withLogin("retail", corpus(), function()
    A.eq(_G.C_AddOns.GetNumAddOns(), 3)
    A.same({ _G.C_AddOns.GetAddOnInfo("Spare") }, { "Spare", "Spare", "spare", true, nil, "INSECURE" })
    A.same({ _G.C_AddOns.GetAddOnInfo("P") }, { "P", "Plugin", nil, true, nil, "INSECURE" })
    A.eq(select("#", _G.C_AddOns.GetAddOnInfo("P")), 6)
  end)
end

-- source: confirmed (row G15) the old call takes an index as well as a name; assumed (row G15) the list is sorted by
-- name.
local function test_info_takes_an_index_in_sorted_order_assumed()
  withLogin("retail", corpus(), function()
    A.eq(_G.C_AddOns.GetAddOnInfo(1), "HandyNotes")
    A.eq(_G.C_AddOns.GetAddOnInfo(3), "Spare")
    A.eq(_G.C_AddOns.GetAddOnInfo(4), nil)
  end)
end

-- source: assumed (row G15) LoadAddOn answers true, or nil and a reason; an addon the mock names without a folder
-- counts as installed.
local function test_load_on_demand_and_enable_flags_assumed()
  withLogin("vanilla", corpus(), function()
    _G.C_AddOns.DisableAddOn("Spare")
    A.same({ _G.C_AddOns.LoadAddOn("Spare") }, { nil, "DISABLED" })
    A.same({ _G.C_AddOns.GetAddOnInfo("Spare") }, { "Spare", "Spare", "spare", false, "DISABLED", "INSECURE" })
    _G.C_AddOns.EnableAddOn("Spare")
    A.eq(_G.C_AddOns.LoadAddOn("Spare"), true)
    A.eq(_G.C_AddOns.IsAddOnLoaded("Spare"), true)
    A.same({ _G.C_AddOns.LoadAddOn("Nope") }, { nil, "MISSING" })
  end)
end

-- source: confirmed (row G15) ADDON_LOADED fires per addon after its files; a loaded addon is not loaded twice.
local function test_load_on_demand_fires_addon_loaded_once()
  withLogin("retail", corpus(), function()
    local before = #_G.SEEN
    _G.C_AddOns.LoadAddOn("Spare")
    _G.C_AddOns.LoadAddOn("Spare")
    A.eq(#_G.SEEN, before + 1)
    A.eq(_G.SEEN[#_G.SEEN], "Spare")
  end)
end

-- source: confirmed (row G16) a dependency loads before the addon that lists it, also on demand.
local function test_load_on_demand_loads_dependencies_first()
  local dir = corpus()
  addon(dir, "Late", "## Dependencies: Lib\n", WATCH)
  addon(dir, "Lib", "", WATCH)
  withLogin("retail", dir, function()
    A.eq(_G.C_AddOns.LoadAddOn("Late"), true)
    A.same({ _G.SEEN[#_G.SEEN - 1], _G.SEEN[#_G.SEEN] }, { "Lib", "Late" })
    A.eq(_G.C_AddOns.IsAddOnLoaded("Lib"), true)
  end)
end

-- source: assumed (row G15) a load that fails answers nil and the client's reason code: DEP_MISSING for a missing
-- dependency, INCOMPATIBLE for an addon the flavor does not declare.
local function test_load_on_demand_failures_name_a_reason_assumed()
  local dir = corpus()
  addon(dir, "NeedsGone", "## Dependencies: Gone\n")
  addon(dir, "OnlyVanilla", "")
  fs.writeFile(dir .. "/OnlyVanilla/OnlyVanilla.toc", "## Interface-Vanilla: 11509\nOnlyVanilla.lua\n")
  withLogin("retail", dir, function()
    A.same({ _G.C_AddOns.LoadAddOn("NeedsGone") }, { nil, "DEP_MISSING" })
    A.same({ _G.C_AddOns.LoadAddOn("OnlyVanilla") }, { nil, "INCOMPATIBLE" })
    A.eq(_G.C_AddOns.IsAddOnLoaded("NeedsGone"), false)
  end)
end

-- source: assumed (row G15) an addon the mock names without a folder is installed, with the mock's fields.
local function test_mock_addons_need_no_folder_assumed()
  G.withGame("retail", function(w)
    w:setMock({ addons = { Fake = { loaded = true, meta = { Title = "Fake Title", Notes = "n" } } } })
    A.eq(_G.C_AddOns.GetNumAddOns(), 1)
    A.same({ _G.C_AddOns.GetAddOnInfo("Fake") }, { "Fake", "Fake Title", "n", true, nil, "INSECURE" })
    A.eq(_G.C_AddOns.IsAddOnLoaded("Fake"), true)
    A.eq(_G.C_AddOns.LoadAddOn("Fake"), true)
    A.same(w.unscripted, {})
  end)
end

-- source: assumed (row G15) false is how a scenario clears an addon (a mock patch never deletes): the addon counts as
-- absent, so no reader indexes it.
local function test_an_addon_cleared_with_false_is_absent_assumed()
  G.withGame("retail", function(w)
    w:setMock({ addons = { Gone = { loaded = true } } })
    A.eq(_G.C_AddOns.GetNumAddOns(), 1)
    w:setMock({ addons = { Gone = false } })
    A.eq(_G.C_AddOns.GetNumAddOns(), 0)
    A.same({ _G.C_AddOns.IsAddOnLoaded("Gone") }, { false, false })
    A.eq(_G.C_AddOns.GetAddOnInfo("Gone"), nil)
    A.eq(_G.C_AddOns.GetAddOnMetadata("Gone", "Title"), nil)
    A.same({ pcall(_G.C_AddOns.LoadAddOn, "Gone") }, { true, nil, "MISSING" })
    _G.C_AddOns.EnableAddOn("Gone")
    A.eq(_G.C_AddOns.GetNumAddOns(), 0)
  end)
end

-- source: assumed (row G15) a dependency cleared with false is not loaded, so it loads from its folder.
local function test_a_dependency_cleared_with_false_loads_from_its_folder_assumed()
  local dir = corpus()
  addon(dir, "Late", "## Dependencies: Lib\n", WATCH)
  addon(dir, "Lib", "", WATCH)
  withLogin("retail", dir, function(_, w)
    w:setMock({ addons = { Lib = false } })
    A.eq(_G.C_AddOns.LoadAddOn("Late"), true)
    A.eq(_G.C_AddOns.IsAddOnLoaded("Lib"), true)
  end)
end

-- source: assumed (row G15) an addon that is not installed answers the defaults; the kit knows the addons folder, so
-- that is a scripted answer (addons probe optional integrations this way), not an unscripted one.
local function test_an_uninstalled_addon_answers_defaults_as_scripted_assumed()
  G.withGame("retail", function(w)
    A.same({ _G.C_AddOns.IsAddOnLoaded("Nobody") }, { false, false })
    A.eq(_G.C_AddOns.GetAddOnMetadata("Nobody", "Title"), nil)
    A.eq(_G.C_AddOns.GetAddOnInfo("Nobody"), nil)
    A.same(w.unscripted, {})
  end)
end

-- source: confirmed (row G1) the bare addon calls exist on no flavor; ReloadUI, Logout and Quit exist on all.
local function test_bare_addon_globals_are_absent_and_reload_calls_are_present()
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function()
      for _, name in ipairs({ "IsAddOnLoaded", "GetAddOnMetadata", "GetAddOnInfo", "GetNumAddOns", "LoadAddOn", "EnableAddOn", "DisableAddOn" }) do
        A.eq(rawget(_G, name), nil, flavor .. " " .. name)
      end
      for _, name in ipairs({ "ReloadUI", "Logout", "Quit" }) do
        A.eq(type(rawget(_G, name)), "function", flavor .. " " .. name)
      end
    end)
  end
end

-- source: confirmed (row G15) ReloadUI reloads the interface; assumed (row G15) the kit sets a flag a session reads, and
-- Logout and Quit end nothing.
local function test_reload_ui_flags_and_logout_quit_are_scripted_assumed()
  G.withGame("retail", function(w)
    A.eq(w.reloadRequested, nil)
    _G.ReloadUI()
    A.eq(w.reloadRequested, true)
    _G.Logout()
    _G.Quit()
    A.eq(w.unscripted.Logout, nil)
    A.eq(w.unscripted.Quit, nil)
    A.eq(w.unscripted.ReloadUI, nil)
  end)
end

return function()
  test_loaded_state_and_metadata()
  test_counts_and_info_list_installed_addons_assumed()
  test_info_takes_an_index_in_sorted_order_assumed()
  test_load_on_demand_and_enable_flags_assumed()
  test_load_on_demand_fires_addon_loaded_once()
  test_load_on_demand_loads_dependencies_first()
  test_load_on_demand_failures_name_a_reason_assumed()
  test_mock_addons_need_no_folder_assumed()
  test_an_addon_cleared_with_false_is_absent_assumed()
  test_a_dependency_cleared_with_false_loads_from_its_folder_assumed()
  test_an_uninstalled_addon_answers_defaults_as_scripted_assumed()
  test_bare_addon_globals_are_absent_and_reload_calls_are_present()
  test_reload_ui_flags_and_logout_quit_are_scripted_assumed()
end
