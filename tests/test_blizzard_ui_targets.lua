-- The Blizzard UI layer's default targets (blizzard_ui.lua M.TARGETS): what a load with no opts.targets brings in. The
-- extract is a kit-authored mini one (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")

-- Blizzard_EditMode's login layout pass indexes OverrideActionBar.xpBar (retail editmodemanager.lua:641); without the
-- addon the pass stops there and the main action bar never leaves the top-left corner.
local function test_default_targets_load_the_override_action_bar()
  local oab = { toc = "## Interface: 120100\noab.lua\n", files = { ["oab.lua"] = "OverrideActionBar = {}\n" } }
  local addons = B.mini({ blizzard_overrideactionbar = oab })
  B.run(addons, {}, function(s)
    A.contains(s.w.blizzard.loaded, "Blizzard_OverrideActionBar")
    A.eq(type(_G.OverrideActionBar), "table")
  end)
end

-- source: BU25 the classic frame position manager indexes ChatFrame1 (tbc uiparentpanelmanageroverrides.lua:73, :100) and
-- Edit Mode indexes CompactPartyFrame (EditModeSystemTemplates.lua:1517); on tbc nothing the other targets depend on
-- loads their addons, so without them both read nil and the cast bar is never placed.
local function test_default_targets_load_the_chat_and_raid_frames()
  local function addon(lua)
    return { toc = "## Interface: 120100\nmain.lua\n", files = { ["main.lua"] = lua } }
  end
  local addons = B.mini({
    blizzard_chatframe = addon("ChatFrame1 = {}\n"),
    blizzard_compactraidframes = addon("CompactPartyFrame = {}\n"),
  })
  B.run(addons, {}, function(s)
    A.contains(s.w.blizzard.loaded, "Blizzard_ChatFrame")
    A.contains(s.w.blizzard.loaded, "Blizzard_CompactRaidFrames")
    A.same({ type(_G.ChatFrame1), type(_G.CompactPartyFrame) }, { "table", "table" })
  end)
end

-- source: BU27 Edit Mode's micro menu anchor pass calls QueueStatusButton:UpdateDefaultAnchor() (forever
-- EditModeSystemTemplates.lua:2467); on forever only Minimap's classic-only Dep names Blizzard_QueueStatusFrame, so
-- without it as a target the button reads nil.
local function test_default_targets_load_the_queue_status_frame()
  local qsf = { toc = "## Interface: 120100\nmain.lua\n", files = { ["main.lua"] = "QueueStatusButton = {}\n" } }
  B.run(B.mini({ blizzard_queuestatusframe = qsf }), {}, function(s)
    A.contains(s.w.blizzard.loaded, "Blizzard_QueueStatusFrame")
    A.eq(type(_G.QueueStatusButton), "table")
  end)
end

-- source: BU28 the panel manager's IsOptionFrameOpen indexes GameMenuFrame unguarded (tbc
-- uiparentpanelmanager.lua:1140), which ToggleAllBags reaches; no other target's dependency names Blizzard_GameMenu.
local function test_default_targets_load_the_game_menu()
  local menu = { toc = "## Interface: 120100\nmain.lua\n", files = { ["main.lua"] = "GameMenuFrame = {}\n" } }
  B.run(B.mini({ blizzard_gamemenu = menu }), {}, function(s)
    A.contains(s.w.blizzard.loaded, "Blizzard_GameMenu")
    A.eq(type(_G.GameMenuFrame), "table")
  end)
end

-- source: BU29 the classic bag frame checks the backpack button when it opens (tbc containerframe_shared.lua:270
-- MainMenuBarBackpackButton:SetChecked); no other target's dependency names Blizzard_MainMenuBarBagButtons.
local function test_default_targets_load_the_bag_buttons()
  local bags = { toc = "## Interface: 120100\nmain.lua\n", files = { ["main.lua"] = "MainMenuBarBackpackButton = {}\n" } }
  B.run(B.mini({ blizzard_mainmenubarbagbuttons = bags }), {}, function(s)
    A.contains(s.w.blizzard.loaded, "Blizzard_MainMenuBarBagButtons")
    A.eq(type(_G.MainMenuBarBackpackButton), "table")
  end)
end

-- source: BU31 the camelot character frame hides every name in CHARACTERFRAME_SUBFRAMES unguarded (forever
-- camelot/characterframe.lua:113), among them TokenFrame (Blizzard_TokenUI) and StatisticsFrame (Blizzard_Statistics).
local function test_default_targets_load_the_character_subframe_addons()
  local token = { toc = "## Interface: 120100\nmain.lua\n", files = { ["main.lua"] = "TokenFrame = {}\n" } }
  local stats = { toc = "## Interface: 120100\nmain.lua\n", files = { ["main.lua"] = "StatisticsFrame = {}\n" } }
  B.run(B.mini({ blizzard_tokenui = token, blizzard_statistics = stats }), {}, function(s)
    A.contains(s.w.blizzard.loaded, "Blizzard_TokenUI")
    A.contains(s.w.blizzard.loaded, "Blizzard_Statistics")
    A.same({ type(_G.TokenFrame), type(_G.StatisticsFrame) }, { "table", "table" })
  end)
end

return function()
  test_default_targets_load_the_character_subframe_addons()
  test_default_targets_load_the_bag_buttons()
  test_default_targets_load_the_override_action_bar()
  test_default_targets_load_the_chat_and_raid_frames()
  test_default_targets_load_the_queue_status_frame()
  test_default_targets_load_the_game_menu()
end
