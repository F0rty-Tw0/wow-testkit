-- Session and client fakes: locale, realm, CVars, login state, client platform, frame rate, network stats and the
-- server clock, all read from w.mock; w:setMock merging; Game.install sharing a mock table that exists already.
local A = require("assert")
local G = require("tests.helpers.game")
local Game = require("game")
local Scenario = require("scenario")
local World = require("world")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/game/[^/]*$") or "tests"
local GOOD = TEST_DIR .. "/fixtures/smoke/Good"

local function test_locale_and_realm_follow_the_mock() -- (G2)
  G.withGame("retail", function(w)
    A.eq(_G.GetLocale(), "enUS")
    w:setMock({ locale = "deDE", realm = "Kirin Tor" })
    A.same({ _G.GetLocale(), _G.GetRealmName(), _G.GetNormalizedRealmName() }, { "deDE", "Kirin Tor", "KirinTor" })
  end)
end

local function test_normalized_realm_drops_spaces_hyphens_and_periods() -- (G2)
  G.withGame("retail", function(w)
    w:setMock({ realm = "Azjol-Nerub St. Mary" })
    A.eq(_G.GetNormalizedRealmName(), "AzjolNerubStMary")
  end)
end

local function test_set_mock_merges_nested_tables()
  G.withGame("retail", function(w)
    w:setMock({ modifiers = { shift = true } })
    w:setMock({ modifiers = { ctrl = true } })
    A.same(w.mock.modifiers, { shift = true, ctrl = true })
  end)
end

local function test_set_mock_copies_the_patch_tables()
  G.withGame("retail", function(w)
    local patch = { modifiers = { shift = true } }
    w:setMock(patch)
    w:setMock({ modifiers = { ctrl = true } })
    A.same(patch, { modifiers = { shift = true } })
  end)
end

local function test_set_mock_replaces_a_non_table_value()
  G.withGame("retail", function(w)
    w:setMock({ locale = { "x" } })
    w:setMock({ locale = "frFR" })
    A.eq(_G.GetLocale(), "frFR")
  end)
end

local function test_install_keeps_an_existing_mock_table()
  local w = World.new({ flavor = "retail" })
  w.mock = { modifiers = { shift = true }, combat = false, group = "none" } -- Task 5.4's shape, set first
  local before = w.mock
  Game.install(w)
  A.same({ w.mock == before, w.mock.modifiers.shift, w.mock.locale, w.mock.group }, { true, true, "enUS", "none" })
  w:destroy()
end

local function test_cvars_are_case_insensitive_strings() -- (G3)
  G.withGame("vanilla", function()
    A.eq(_G.GetCVar("nope"), nil)
    _G.SetCVar("Foo", 1)
    A.same({ _G.GetCVar("foo"), _G.GetCVarBool("foo"), _G.GetCVarBool("nope") }, { "1", true, false })
  end)
end

local function test_set_cvar_stores_the_string_form() -- (G3)
  G.withGame("retail", function()
    _G.SetCVar("a", true)
    _G.SetCVar("b", false)
    _G.SetCVar("c", 2.5)
    A.same({ _G.GetCVar("a"), _G.GetCVar("b"), _G.GetCVar("c") }, { "1", "0", "2.5" })
    A.same({ _G.GetCVarBool("a"), _G.GetCVarBool("b") }, { true, false })
  end)
end

-- TextSizeManager.lua (Blizzard_AccessibilityTemplates) takes math.max of GetCVarNumberOrDefault("userFontScale"), which
-- falls back to GetCVarDefault; an unset CVar reads as its default until SetCVar changes it.
local function test_unset_cvar_reads_its_client_default() -- (G29)
  G.withGame("retail", function()
    A.same({ _G.GetCVar("userFontScale"), _G.GetCVarDefault("UserFontScale") }, { "1.000000", "1.000000" })
    A.eq(_G.C_CVar.GetCVarDefault("userFontScale"), "1.000000")
    _G.SetCVar("userFontScale", 1.5)
    A.same({ _G.GetCVar("userFontScale"), _G.GetCVarDefault("userFontScale") }, { "1.5", "1.000000" })
    A.eq(_G.GetCVarDefault("nope"), nil)
  end)
end

-- Nameplates.lua:799 (Blizzard_SettingsDefinitions_Frame, tbc and forever) passes both nameplate class colour defaults to
-- bit.bor; unknown, they were nil and the bor raised at load. Only retail's live branch defaults them on. (G70, G80)
local function test_nameplate_class_colour_defaults_follow_the_branch()
  for flavor, want in pairs({ tbc = "0", vanilla = "0", mists = "0", retail = "1", forever = "0" }) do
    G.withGame(flavor, function()
      A.same({
        _G.GetCVarDefault("nameplateShowClassColor"),
        _G.GetCVarDefault("nameplateShowFriendlyClassColor"),
        _G.GetCVar("nameplateShowClassColor"),
      }, { want, want, want }, flavor)
    end)
  end
end

-- Graphics.lua (Blizzard_SettingsDefinitions_Shared; tbc :510, forever :755) asserts the gxMonitor default is 0 at load;
-- unknown, it was nil and the assert raised. (G79)
local function test_monitor_default_is_the_primary_monitor()
  for _, flavor in ipairs({ "tbc", "forever" }) do
    G.withGame(flavor, function()
      A.same({ _G.GetCVarDefault("gxMonitor"), _G.C_CVar.GetCVarDefault("gxMonitor") }, { "0", "0" }, flavor)
    end)
  end
end

-- Graphics.lua Register (tbc :1299, forever :1555) subtracts tonumber(GetCVarDefault("ResampleSharpness")) from the
-- slider's max; unknown, it was nil and the arithmetic raised at load. Every CVar the dump lists has its default. (G80)
local function test_every_dumped_cvar_reads_its_branch_default()
  for flavor, want in pairs({ tbc = "1", forever = "1.000000" }) do
    G.withGame(flavor, function()
      A.same({
        _G.GetCVarDefault("ResampleSharpness"),
        _G.C_CVar.GetCVarDefault("resampleSharpness"),
        _G.GetCVar("userFontScale"),
      }, { "0.2", "0.2", want }, flavor)
    end)
  end
end

local function test_namespaced_cvars_share_the_store() -- (G3)
  G.withGame("retail", function()
    _G.C_CVar.SetCVar("Bar", "7")
    A.same({ _G.GetCVar("bar"), _G.C_CVar.GetCVar("BAR"), _G.C_CVar.GetCVarBool("bar") }, { "7", "7", false })
  end)
end

local function test_logged_in_flips_at_player_login_assumed() -- (G4)
  local before, during
  local results = Scenario.matrix({ "retail" }, function(s)
    before = _G.IsLoggedIn()
    local f = _G.CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
      during = _G.IsLoggedIn()
    end)
    s:login()
  end, { addon = "Good", root = GOOD })
  A.same({ before, during, results.retail.status }, { nil, true, "pass" })
end

local function test_logged_in_is_nil_without_a_login() -- (G4)
  G.withGame("retail", function()
    A.eq(_G.IsLoggedIn(), nil)
  end)
end

local function test_server_time_follows_the_world_clock() -- (G5)
  G.withGame("retail", function(w)
    w:setMock({ serverTime = 1000 })
    A.eq(_G.GetServerTime(), 1000)
    w:advance(5)
    A.eq(_G.GetServerTime(), 1005)
  end)
end

local function test_server_time_counts_whole_seconds_from_the_world_start() -- (G5)
  G.withGame("retail", function(w)
    local start = _G.GetServerTime()
    w:advance(2.75)
    A.eq(_G.GetServerTime(), start + 2)
  end)
end

-- tbc GameTimeFrame_Update (gametime_nocalendar.lua:17-18) computes (hour * 60) + minute from GetGameTime(); a bare
-- global with no signature, it answered nothing and the arithmetic raised at load. (G65)
local function test_game_time_is_the_server_clock_hour_and_minute_assumed()
  G.withGame("tbc", function(w)
    w:setMock({ serverTime = 2 * 86400 + 13 * 3600 + 7 * 60 + 59 })
    A.same({ _G.GetGameTime() }, { 13, 7 })
  end)
end

local function test_kit_values_and_client_flags_assumed() -- (G5)
  G.withGame("retail", function(w)
    A.same({ _G.GetFramerate(), _G.GetNetStats() }, { 60, 0.5, 0.5, 30, 40 })
    A.same({ _G.IsWindowsClient(), _G.IsMacClient() }, { true, false })
    w:setMock({ client = "mac" })
    A.same({ _G.IsWindowsClient(), _G.IsMacClient() }, { false, true })
  end)
end

local function test_net_stats_keep_four_values_in_an_addon_call() -- (G5)
  G.withGame("retail", function(w)
    w:setMock({ net = { latencyWorld = 99 } })
    local values = w:run("addon", function()
      return { _G.GetNetStats() }
    end)
    A.same(values, { 0.5, 0.5, 30, 99 })
  end)
end

local function test_scenario_mock_patches_the_world() -- (G2)
  local locale
  local results = Scenario.matrix({ "retail" }, function(s)
    s:mock({ locale = "koKR" })
    locale = _G.GetLocale()
  end, { addon = "Good", root = GOOD })
  A.same({ locale, results.retail.status }, { "koKR", "pass" })
end

local function test_names_the_flavor_lacks_stay_absent()
  G.withGame("retail", function(w)
    A.eq(Game.define(w, "NoSuchGameFunction", function() end), false)
    A.eq(rawget(_G, "NoSuchGameFunction"), nil)
    A.eq(Game.define(w, "NoSuchGameFunction", function() end, { "vanilla" }), false)
    A.eq(Game.define(w, "NoSuchGameFunction", function() end, { "retail" }), true)
    A.eq(type(rawget(_G, "NoSuchGameFunction")), "function")
  end)
end

local function test_define_listing_other_flavors_keeps_names_the_data_has()
  G.withGame("retail", function(w)
    A.eq(
      Game.define(w, "GetLocale", function()
        return "xx"
      end, { "vanilla" }),
      true
    )
    A.eq(_G.GetLocale(), "xx")
  end)
end

return function()
  test_locale_and_realm_follow_the_mock()
  test_normalized_realm_drops_spaces_hyphens_and_periods()
  test_set_mock_merges_nested_tables()
  test_set_mock_copies_the_patch_tables()
  test_set_mock_replaces_a_non_table_value()
  test_install_keeps_an_existing_mock_table()
  test_cvars_are_case_insensitive_strings()
  test_set_cvar_stores_the_string_form()
  test_namespaced_cvars_share_the_store()
  test_unset_cvar_reads_its_client_default()
  test_nameplate_class_colour_defaults_follow_the_branch()
  test_monitor_default_is_the_primary_monitor()
  test_every_dumped_cvar_reads_its_branch_default()
  test_logged_in_flips_at_player_login_assumed()
  test_logged_in_is_nil_without_a_login()
  test_server_time_follows_the_world_clock()
  test_server_time_counts_whole_seconds_from_the_world_start()
  test_kit_values_and_client_flags_assumed()
  test_game_time_is_the_server_clock_hour_and_minute_assumed()
  test_net_stats_keep_four_values_in_an_addon_call()
  test_scenario_mock_patches_the_world()
  test_names_the_flavor_lacks_stay_absent()
  test_define_listing_other_flavors_keeps_names_the_data_has()
end
