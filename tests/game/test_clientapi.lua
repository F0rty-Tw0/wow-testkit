-- Client APIs that Blizzard's own UI code calls while it loads (the real-extract loop of Task 10.2). Each test names the
-- Blizzard file that needed the call; answers are assumed unless a source is named.
local A = require("assert")
local AddonEnv = require("addon_env")
local G = require("tests.helpers.game")

-- Color.lua (Blizzard_SharedXMLBase) writes global names through GetCurrentEnvironment(): the one _G addon code sees.
local function test_get_current_environment_is_the_addon_global_table_assumed()
  G.withGame("retail", function(w)
    A.truthy(_G.GetCurrentEnvironment() == AddonEnv.global(w, "_G"), "the addon view of _G")
  end)
end

-- CurveConstants.lua (Blizzard_SharedXMLBase) builds four curves from C_CurveUtil.CreateCurve at load.
local function test_curve_object_evaluates_its_points_assumed()
  G.withGame("retail", function()
    local curve = _G.C_CurveUtil.CreateCurve()
    curve:SetType(_G.Enum.LuaCurveType.Linear)
    curve:AddPoint(0.0, 0)
    curve:AddPoint(1.0, 100)
    A.same({ curve:GetPointCount(), curve:Evaluate(0.25), curve:Evaluate(-1), curve:Evaluate(2) }, { 2, 25, 0, 100 })
    curve:SetType(_G.Enum.LuaCurveType.Step)
    A.same({ curve:GetType(), curve:Evaluate(0.5) }, { 1, 0 })
    curve:ClearPoints()
    A.eq(curve:GetPointCount(), 0)
  end)
end

-- ColorManager.lua (Blizzard_Colors) calls color:GenerateHexColorMarkup() on what C_ColorOverrides answers, so the
-- answer carries Blizzard's ColorMixin when that is loaded.
local function test_quality_colors_carry_the_color_mixin_assumed()
  G.withGame("retail", function(w)
    local plain = _G.C_ColorOverrides.GetColorForQuality(4)
    A.same({ plain.r, plain.g, plain.b, plain.a }, { 0.64, 0.21, 0.93, 1 })
    w:setGlobal("ColorMixin", {
      GetRGB = function(self)
        return self.r, self.g, self.b
      end,
    })
    A.same({ _G.C_ColorOverrides.GetColorForQuality(1):GetRGB() }, { 1, 1, 1 })
  end)
end

-- SecureTemplates.lua (Blizzard_FrameXML) starts with CopyTable(GetFrameMetatable().__index); a nil there aborted the
-- file and left SecureActionButtonMixin (CalculateAction) undefined for every Blizzard action button.
local function test_metatable_getters_answer_the_widget_class_metatable_assumed()
  G.withGame("retail", function()
    local frame = _G.CreateFrame("Frame")
    A.truthy(getmetatable(frame) == _G.GetFrameMetatable(), "Frame")
    A.truthy(getmetatable(_G.CreateFrame("Button")) == _G.GetButtonMetatable(), "Button")
    A.truthy(getmetatable(_G.CreateFrame("EditBox")) == _G.GetEditBoxMetatable(), "EditBox")
    A.truthy(getmetatable(frame:CreateFontString()) == _G.GetFontStringMetatable(), "FontString")
    A.eq(type(_G.GetFrameMetatable().__index.SetSize), "function")
  end)
end

-- SecureTemplates.lua (Blizzard_FrameXML) keys a table by the main hand and off-hand slot ids at load; a nil key
-- aborted the rest of the file.
local function test_inventory_slot_names_answer_their_ids_assumed()
  G.withGame("retail", function()
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("MainHandSlot"), 16)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("SecondaryHandSlot"), 17)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("HeadSlot"), 1)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("TabardSlot"), 19)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("NoSuchSlot"), nil)
  end)
end

-- Blizzard's transmog code passes "HEADSLOT" and "SHOULDERSLOT" (blizzard_transmog.lua, blizzard_transmogshared.lua) where
-- securetemplates.lua:464 passes "MainHandSlot", to the same call, so the lookup ignores case. With a nil id
-- TransmogUtil.GetSlotID raised "table index is nil" and the transmog window built no slot.
local function test_inventory_slot_names_ignore_case()
  G.withGame("retail", function()
    A.same({ _G.C_PaperDollInfo.GetInventorySlotInfo("HEADSLOT"), _G.C_PaperDollInfo.GetInventorySlotInfo("shoulderslot") }, { 1, 3 })
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo("NOSUCHSLOT"), nil)
    A.eq(_G.C_PaperDollInfo.GetInventorySlotInfo(nil), nil)
  end)
end

-- Blizzard_TalentUI (Classic/Blizzard_TalentUI.lua:159) calls ClassicExpansionAtLeast(LE_EXPANSION_WRATH_OF_THE_LICH_KING) in its
-- OnLoad; with the constant nil the call raised a bad-argument error and the talent frame never finished loading.
local function test_classic_expansion_level_and_constants_answer_per_flavor_assumed()
  for flavor, level in pairs({ vanilla = 0, tbc = 1, mists = 4 }) do
    G.withGame(flavor, function()
      A.same({ _G.LE_EXPANSION_BURNING_CRUSADE, _G.LE_EXPANSION_MISTS_OF_PANDARIA, _G.GetClassicExpansionLevel() }, { 1, 4, level }, flavor)
      A.eq(_G.ClassicExpansionAtLeast(_G.LE_EXPANSION_WRATH_OF_THE_LICH_KING), level >= 2, flavor)
    end)
  end
  G.withGame("retail", function()
    A.eq(_G.LE_EXPANSION_BURNING_CRUSADE, nil)
  end)
end

-- The classic UIParent (tbc uiparent.lua:24-28) builds ITEM_QUALITY_COLORS for 0 .. NUM_LE_ITEM_QUALITYS - 1 and the auction
-- list (Blizzard_AuctionUI.lua:1013) indexes it by quality; with the names nil the table stayed empty.
local function test_legacy_item_quality_names_alias_enum_item_quality_assumed() -- (G26)
  for _, flavor in ipairs({ "vanilla", "tbc", "mists" }) do
    G.withGame(flavor, function()
      A.same({ _G.LE_ITEM_QUALITY_POOR, _G.LE_ITEM_QUALITY_COMMON, _G.LE_ITEM_QUALITY_UNCOMMON, _G.LE_ITEM_QUALITY_RARE }, { 0, 1, 2, 3 }, flavor)
      A.same({ _G.LE_ITEM_QUALITY_HEIRLOOM, _G.LE_ITEM_QUALITY_WOW_TOKEN, _G.NUM_LE_ITEM_QUALITYS }, { 7, 8, 9 }, flavor)
    end)
  end
  G.withGame("retail", function() -- no retail-loaded file reads them
    A.same({ _G.LE_ITEM_QUALITY_COMMON, _G.NUM_LE_ITEM_QUALITYS }, {})
  end)
end

local function test_kiosk_mode_is_off_assumed() -- Blizzard_MicroMenu calls Kiosk.IsEnabled() from UpdateMicroButtons
  for _, flavor in ipairs({ "retail", "tbc" }) do
    G.withGame(flavor, function()
      A.eq(_G.Kiosk.IsEnabled(), false, flavor)
    end)
  end
end

-- confirmed: paperdollframe.lua:617 reads _G["SPELL_STAT" .. statIndex .. "_NAME"] for statIndex = LE_UNIT_STAT_*, and
-- the retail strings name SPELL_STAT1..5 Strength, Agility, Stamina, Intellect, Spirit.
local function test_unit_stat_constants_index_the_stat_names()
  G.withGame("retail", function()
    A.same(
      { _G.LE_UNIT_STAT_STRENGTH, _G.LE_UNIT_STAT_AGILITY, _G.LE_UNIT_STAT_STAMINA, _G.LE_UNIT_STAT_INTELLECT, _G.LE_UNIT_STAT_SPIRIT },
      { 1, 2, 3, 4, 5 }
    )
  end)
end

local function test_class_info_answers_the_class_list_assumed() -- Blizzard_PlayerSpellsFrame.lua:340 reads .classFile of it
  G.withGame("retail", function()
    A.same(_G.C_CreatureInfo.GetClassInfo(1), { className = "Warrior", classFile = "WARRIOR", classID = 1 })
    A.same(_G.C_CreatureInfo.GetClassInfo(13), { className = "Evoker", classFile = "EVOKER", classID = 13 })
    A.eq(_G.C_CreatureInfo.GetClassInfo(99), nil)
  end)
end

-- Blizzard_WorldMap.lua:577 (ToggleWorldMap) indexes Enum.GameRule.WorldMapDisabled; no installed data lists the members, so
-- the kit's table is empty and every rule reads as inactive.
local function test_game_rule_enum_is_empty_so_no_rule_is_active_assumed()
  G.withGame("retail", function()
    A.same({ type(_G.Enum.GameRule), _G.Enum.GameRule.WorldMapDisabled }, { "table", nil })
    A.eq(_G.C_GameRules.IsGameRuleActive(_G.Enum.GameRule.WorldMapDisabled), false)
  end)
  G.withGame("tbc", function()
    A.eq(_G.Enum.GameRule, nil) -- the classic data has no GameRule; the kit adds none
  end)
end

-- ActionButton.lua (Blizzard_ActionBar) compares C_GameRules.GetActiveGameMode() with Enum.GameMode.Plunderstorm on
-- every button update, and tbc's GameRulesUtil.lua indexes it at file scope; source: row G28, the member values of
-- Ketho's retail LuaEnum dump (assumed the same off retail).
local function test_game_mode_enum_has_the_client_members()
  for _, flavor in ipairs({ "retail", "tbc" }) do
    G.withGame(flavor, function()
      local mode = _G.Enum.GameMode
      A.same({ mode.Standard, mode.Plunderstorm, mode.WoWHack }, { 1, 2, 3 }, flavor)
    end)
  end
end

-- EventUtil.lua (Blizzard_SharedXML) asserts C_EventUtils.IsEventValid on each event ContinueAfterAllEvents waits for.
local function test_event_is_valid_when_the_flavor_knows_the_event_assumed()
  for _, flavor in ipairs({ "retail", "tbc" }) do
    G.withGame(flavor, function()
      A.same({
        _G.C_EventUtils.IsEventValid("VARIABLES_LOADED"),
        _G.C_EventUtils.IsEventValid("PLAYER_LOGIN"),
        _G.C_EventUtils.IsEventValid("NOT_AN_EVENT"),
      }, { true, true, false }, flavor)
    end)
  end
end

return function()
  test_game_mode_enum_has_the_client_members()
  test_event_is_valid_when_the_flavor_knows_the_event_assumed()
  test_legacy_item_quality_names_alias_enum_item_quality_assumed()
  test_game_rule_enum_is_empty_so_no_rule_is_active_assumed()
  test_class_info_answers_the_class_list_assumed()
  test_unit_stat_constants_index_the_stat_names()
  test_kiosk_mode_is_off_assumed()
  test_classic_expansion_level_and_constants_answer_per_flavor_assumed()
  test_inventory_slot_names_answer_their_ids_assumed()
  test_inventory_slot_names_ignore_case()
  test_metatable_getters_answer_the_widget_class_metatable_assumed()
  test_quality_colors_carry_the_color_mixin_assumed()
  test_curve_object_evaluates_its_points_assumed()
  test_get_current_environment_is_the_addon_global_table_assumed()
end
