-- Window plumbing (blizzard_windows.lua, blizzard_window_specs.lua, scenario_windows.lua): load-on-demand Blizzard addons,
-- the per-flavor window matrix (B1), how a window opens (B2) and which addons load with the layer (C3). Every extract is a
-- kit-authored mini one (tests/helpers/blizzard.lua, tests/helpers/windows.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local BlizzardWindows = require("blizzard_windows")
local Flavors = require("tools.flavors")
local W = require("tests.helpers.windows")

local SPEC = { mail = { addon = "Blizzard_MiniWindow", open = "MAIL_SHOW", frame = "MiniWindowFrame" } }
local function before(s)
  s.w.windowSpecs = SPEC
end

-- (B3: a second call returns true is confirmed (wiki); loading dependencies, one ADDON_LOADED and no reload are assumed)
local function test_load_on_demand_addon_loads_once_and_fires_addon_loaded_assumed()
  B.run(B.mini(), { targets = { "Blizzard_MiniBase" }, before = before }, function()
    A.eq(_G.MiniWindowFrame, nil) -- LoadOnDemand: not loaded at login
    A.same({ _G.C_AddOns.LoadAddOn("Blizzard_MiniWindow"), _G.C_AddOns.LoadAddOn("Blizzard_MiniWindow") }, { true, true })
    A.eq(_G.MiniWindowLoads, 1)
    A.eq(_G.MiniLog[#_G.MiniLog], "adl:Blizzard_MiniWindow")
    A.eq(_G.C_AddOns.IsAddOnLoaded("Blizzard_MiniWindow"), true)
  end)
end

local function test_load_on_demand_of_an_absent_blizzard_addon_is_missing()
  B.run(B.mini(), { targets = { "Blizzard_MiniBase" } }, function()
    A.same({ _G.C_AddOns.LoadAddOn("Blizzard_Nope") }, { nil, "MISSING" })
  end)
end

-- (B2)
local function test_open_window_loads_shows_and_falls_back_to_kit_show_ui_panel_assumed()
  B.run(B.mini(), { targets = { "Blizzard_MiniBase" }, before = before }, function(s)
    s:openWindow("mail", { inbox = {} })
    A.eq(_G.MiniWindowFrame:IsShown(), true)
    A.same(BlizzardWindows.available(s.w), { "mail" })
  end)
end

local function test_open_window_without_the_layer_still_fires_the_event()
  W.scenario("retail", {}, function(s)
    local log = W.watch(s.w, { "MAIL_SHOW" })
    s:openWindow("mail", { inbox = {} })
    A.same(W.names(log), { "MAIL_SHOW" })
    A.same(BlizzardWindows.available(s.w), {})
  end)
end

local function test_unknown_window_raises()
  W.scenario("retail", {}, function(s)
    local ok, err = pcall(s.openWindow, s, "bank")
    A.same({ ok, err:match("unknown window 'bank'") ~= nil }, { false, true })
  end)
end

-- (B1)
local function test_flavors_without_a_window_raise_unknown_window()
  for flavor, window in pairs({ tbc = "transmog", vanilla = "transmog" }) do
    W.scenario(flavor, {}, function(s)
      local ok, err = pcall(s.openWindow, s, window)
      A.same({ ok, err:match("unknown window '" .. window .. "'") ~= nil }, { false, true }, flavor)
    end)
  end
end

local function test_window_matrix_follows_b1()
  for _, flavor in ipairs(Flavors.list) do
    local specs = BlizzardWindows.WINDOWS[flavor]
    A.eq(specs.map.lod, false, flavor)
    A.eq(specs.transmog ~= nil, flavor == "retail" or flavor == "forever" or flavor == "mists", flavor)
    A.eq(specs.talents ~= nil, true, flavor)
  end
  A.eq(BlizzardWindows.WINDOWS.tbc.merchant.addon, "Blizzard_UIPanels_Game")
  A.eq(BlizzardWindows.WINDOWS.tbc.mail.addon, "Blizzard_UIPanels_Game")
  A.same(BlizzardWindows.WINDOWS.mists.auction.also, { "Blizzard_AuctionHouseUI" })
  A.eq(BlizzardWindows.WINDOWS.retail.mail.addon, "Blizzard_MailFrame")
end

-- (B2, all five flavors)
local function test_interaction_types_resolve_to_the_b2_values()
  for _, flavor in ipairs(Flavors.list) do
    W.withWindows(flavor, {}, function()
      A.same({
        BlizzardWindows.interaction("Merchant"),
        BlizzardWindows.interaction("MailInfo"),
        BlizzardWindows.interaction("Auctioneer"),
        BlizzardWindows.interaction("Transmogrifier"),
      }, { 5, 17, 21, 24 }, flavor)
    end)
  end
end

local INTERACT = { mail = { addon = "Blizzard_MiniWindow", interaction = "MailInfo", open = "MAIL_SHOW", frame = "MiniWindowFrame" } }
-- (B2)
local function test_retail_window_opens_on_the_interaction_event_then_the_legacy_event_assumed()
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = INTERACT
    end,
  }, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "MAIL_SHOW" })
    s:openWindow("mail", { inbox = {} })
    A.same({ W.names(log), log[1][3] }, { { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "MAIL_SHOW" }, 17 })
    A.eq(_G.MiniWindowShownBy, "MAIL_SHOW:nil") -- the frame's last trigger; the first one (interaction:17) also showed it
  end)
end

local SHOWGLOBAL = { mail = { addon = "Blizzard_MiniWindow", show = "MiniWindowShow", frame = "MiniWindowFrame" } }
-- (B2)
local function test_classic_window_without_a_handler_is_shown_through_its_show_global_assumed()
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = SHOWGLOBAL
    end,
  }, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" })
    s:openWindow("mail", { inbox = {} })
    -- no interaction event on a spec without `interaction`; no `open`, so only the show global can have shown it
    A.same({ #log, _G.MiniWindowFrame:IsShown(), _G.MiniWindowShownBy }, { 0, true, "show-global" })
  end)
end

-- (B1, C3)
local function test_startup_lists_the_shared_addons_per_flavor()
  local shared = { "Blizzard_SharedTalentUI", "Blizzard_TransmogShared", "Blizzard_FrameEffects", "Blizzard_WorldMap" }
  W.withWindows("retail", { addons = shared }, function(w)
    A.same(BlizzardWindows.startup(w), { "Blizzard_SharedTalentUI", "Blizzard_TransmogShared", "Blizzard_FrameEffects", "Blizzard_WorldMap" })
  end)
  W.withWindows("tbc", { addons = shared }, function(w)
    A.same(BlizzardWindows.startup(w), { "Blizzard_WorldMap" }) -- the retail names are retail and forever only
  end)
  W.withWindows("retail", { addons = { "Blizzard_WorldMap" } }, function(w) -- a SHARED name the extract lacks is dropped
    A.same(BlizzardWindows.startup(w), { "Blizzard_WorldMap" })
  end)
end

-- (B1, C3)
local function test_classic_merchant_and_mail_share_one_startup_addon()
  W.withWindows("tbc", { addons = { "Blizzard_UIPanels_Game" } }, function(w)
    A.same(BlizzardWindows.startup(w), { "Blizzard_UIPanels_Game" })
  end)
end

-- (B1, R12-a) the folder blizzard_uipanels_game holds only the flavor-suffixed TOC, as in the installed extract
local SUFFIXED = {
  blizzard_uipanels_game = {
    toc = "## Interface: 20506\nSuffixed.lua\n",
    tocFile = "blizzard_uipanels_game_classic.toc",
    files = { ["suffixed.lua"] = "MiniSuffixedLoads = (MiniSuffixedLoads or 0) + 1" },
  },
}
local function test_classic_window_addon_loads_from_its_flavor_suffixed_toc()
  B.run(B.mini(SUFFIXED), { flavor = "tbc", header = "Interface-TBC: 20506" }, function(s)
    A.same({ _G.MiniSuffixedLoads, (_G.C_AddOns.IsAddOnLoaded("Blizzard_UIPanels_Game")) }, { 1, true })
    s:openWindow("merchant", {})
    A.eq(_G.MiniSuffixedLoads, 1) -- already loaded with the layer; opening loads nothing again
  end)
end

local EAGER = { mail = { addon = "Blizzard_MiniEager", lod = false, open = "MAIL_SHOW", frame = "MiniEagerFrame" } }
-- (C3) MINI.blizzard_minieager: the miniwindow addon with no `## LoadOnDemand: 1` line, bumping MiniEagerLoads and
-- creating MiniEagerFrame.
local function test_non_load_on_demand_window_addon_loads_with_the_layer()
  B.run(B.mini(), {
    before = function(s) -- no `targets`: the layer's default list
      s.w.windowSpecs = EAGER
    end,
  }, function(s)
    A.same(BlizzardWindows.startup(s.w), { "Blizzard_MiniEager" })
    A.same({ _G.MiniEagerLoads, _G.MiniEagerFrame ~= nil, (_G.C_AddOns.IsAddOnLoaded("Blizzard_MiniEager")) }, { 1, true, true })
    s:openWindow("mail", { inbox = {} })
    A.eq(_G.MiniEagerLoads, 1) -- opening the window loads nothing again
  end)
end

-- (C3)
local function test_explicit_targets_do_not_pull_in_startup_window_addons()
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = EAGER
    end,
  }, function()
    A.eq(_G.MiniEagerFrame, nil)
  end)
end

-- (B2) the hide event of an interaction window, and HideUIPanel for a show-global window with the layer on
local function test_close_window_fires_the_hide_event_or_hides_the_frame_assumed()
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = INTERACT
    end,
  }, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" })
    s:openWindow("mail", { inbox = {} })
    s:closeWindow("mail")
    A.same({ W.names(log), log[1][3] }, { { "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }, 17 })
  end)
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = SHOWGLOBAL
    end,
  }, function(s)
    s:openWindow("mail", { inbox = {} })
    s:closeWindow("mail")
    A.eq(_G.MiniWindowFrame:IsShown(), false)
  end)
end

local function test_open_window_with_a_missing_addon_notes_it_and_still_fires_the_event_assumed()
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = { mail = { addon = "Blizzard_Absent", open = "MAIL_SHOW" } }
    end,
  }, function(s)
    local log = W.watch(s.w, { "MAIL_SHOW" })
    s:openWindow("mail", { inbox = {} })
    A.same(W.names(log), { "MAIL_SHOW" })
    A.contains(s.notes, "openWindow: Blizzard_Absent missing")
  end)
end

local TALENTS = { talents = { addon = "Blizzard_MiniTalents", toggle = "MiniToggleTalents", frame = "MiniTalentFrame" } }
local TRAITS = {
  configID = 7,
  configs = { [7] = { name = "Kit Build", type = 1, treeIDs = { 790 } } },
  trees = { [790] = { nodes = { 101 } } },
  nodes = { [101] = { entryIDs = { 201 } } },
  entries = { [201] = { definitionID = 301 } },
  definitions = { [301] = { spellID = 9001 } },
}
-- (B4, B6; Task 12.3) the retail window reads the trait store and the spell store; the classic one reads GetTalentInfo
local function test_talent_window_lists_the_tree()
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = TALENTS
      s.w:setMock({ spells = { [9001] = { name = "Kit Strike" } }, traits = TRAITS })
    end,
  }, function(s)
    s:openWindow("talents")
    A.same({ _G.MiniTalentFrame:IsShown(), _G.MiniTalentFrame.lines[1]:GetText() }, { true, "Kit Strike" })
  end)
  B.run(B.mini(), {
    flavor = "tbc",
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = TALENTS
      s.w:setMock({ talents = { tabs = { { name = "T", talents = { { name = "Kit Rage", tier = 1, column = 1, maxRank = 1 } } } } } })
    end,
  }, function(s)
    s:openWindow("talents")
    A.same({ _G.MiniTalentFrame:IsShown(), _G.MiniTalentFrame.lines[1]:GetText() }, { true, "Kit Rage" })
  end)
end

-- (Task 12.3) the opener writes the scenario's talent data and the window sees it
local function test_talents_opener_applies_scenario_data()
  B.run(B.mini(), {
    flavor = "tbc",
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = TALENTS
    end,
  }, function(s)
    s:openWindow("talents", { unspent = 4, tabs = { { name = "T", talents = { { name = "Kit Bolt", tier = 1, column = 1, maxRank = 1 } } } } })
    A.same({ _G.UnitCharacterPoints("player"), _G.MiniTalentFrame.lines[1]:GetText() }, { 4, "Kit Bolt" })
    s:closeWindow("talents")
    A.eq(_G.MiniTalentFrame:IsShown(), false)
  end)
end

return function()
  test_load_on_demand_addon_loads_once_and_fires_addon_loaded_assumed()
  test_load_on_demand_of_an_absent_blizzard_addon_is_missing()
  test_open_window_loads_shows_and_falls_back_to_kit_show_ui_panel_assumed()
  test_open_window_without_the_layer_still_fires_the_event()
  test_unknown_window_raises()
  test_flavors_without_a_window_raise_unknown_window()
  test_window_matrix_follows_b1()
  test_interaction_types_resolve_to_the_b2_values()
  test_retail_window_opens_on_the_interaction_event_then_the_legacy_event_assumed()
  test_classic_window_without_a_handler_is_shown_through_its_show_global_assumed()
  test_startup_lists_the_shared_addons_per_flavor()
  test_classic_merchant_and_mail_share_one_startup_addon()
  test_classic_window_addon_loads_from_its_flavor_suffixed_toc()
  test_non_load_on_demand_window_addon_loads_with_the_layer()
  test_explicit_targets_do_not_pull_in_startup_window_addons()
  test_close_window_fires_the_hide_event_or_hides_the_frame_assumed()
  test_open_window_with_a_missing_addon_notes_it_and_still_fires_the_event_assumed()
  test_talent_window_lists_the_tree()
  test_talents_opener_applies_scenario_data()
end
