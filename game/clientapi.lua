-- Client APIs that Blizzard's own UI code calls while it loads and the other game modules do not own. Each one is here
-- because a real-extract run of the Blizzard UI layer (blizzard_ui.lua) stopped on it.
local M = {}

local AddonEnv = require("addon_env")
local Curve = require("game.curve")
local Items = require("game.items")
local Roster = require("combat_roster_data")
local State = require("game.state")
local define = State.define

M.DEFAULTS = {}

-- A color table of quality's colour (game/items.lua, the kit's one quality colour table); once Blizzard's ColorMixin
-- exists (Blizzard_SharedXMLBase) the table carries its methods.
local function qualityColor(quality)
  local r, g, b = Items.qualityRgb(quality)
  local result = { r = r, g = g, b = b, a = 1 }
  local mixin = rawget(_G, "ColorMixin")
  if type(mixin) ~= "table" then
    return result
  end

  return setmetatable(result, { __index = mixin })
end

-- source: assumed (row G21) the inventory slot ids by slot name (the wiki's InventorySlotId list, from memory), and each
-- slot's empty-slot texture: the fileIDs are confirmed (community listfile, interface/paperdoll/ui-paperdoll-slot-*.blp),
-- the slot to texture pairing is assumed from the file names (the back slot shows the chest texture).
local INVENTORY_SLOTS = {
  HeadSlot = { 1, 136516 },
  NeckSlot = { 2, 136519 },
  ShoulderSlot = { 3, 136526 },
  ShirtSlot = { 4, 136525 },
  ChestSlot = { 5, 136512 },
  WaistSlot = { 6, 136529 },
  LegsSlot = { 7, 136517 },
  FeetSlot = { 8, 136513 },
  WristSlot = { 9, 136530 },
  HandsSlot = { 10, 136515 },
  Finger0Slot = { 11, 136514 },
  Finger1Slot = { 12, 136523 },
  Trinket0Slot = { 13, 136528 },
  Trinket1Slot = { 14, 136528 },
  BackSlot = { 15, 136512 },
  MainHandSlot = { 16, 136518 },
  SecondaryHandSlot = { 17, 136524 },
  RangedSlot = { 18, 136520 },
  TabardSlot = { 19, 136527 },
}

-- source: row G41. The engine's LE_GAME_ERR_<X> message types (UI_ERROR_MESSAGE's first payload), for every name the
-- tbc and forever extracts' Lua reads. No API doc or client dump lists them; the numbers are the idx column of
-- warcraft.wiki.gg Event:UI_ERROR_MESSAGE ("up to date as of Patch 9.2.5 (43971)", and the page warns they shift each
-- patch), so assumed for the kit's builds. Names the table's verbatim part lacks get kit numbers from 100001 (assumed).
local GAME_ERRORS = {
  SYSTEM = 1, SPELL_FAILED_S = 53, ITEM_COOLDOWN = 54, SPELL_COOLDOWN = 57, ABILITY_COOLDOWN = 58,
  SPELL_ALREADY_KNOWN_S = 59, OUT_OF_RANGE = 154, CANT_USE_ITEM = 191, SPELL_FAILED_TOTEMS = 252,
  SPELL_FAILED_REAGENTS = 253, SPELL_FAILED_REAGENTS_GENERIC = 254, SPELL_FAILED_EQUIPPED_ITEM = 257,
  SPELL_FAILED_EQUIPPED_ITEM_CLASS_S = 258, SPELL_FAILED_SHAPESHIFT_FORM_S = 259, SPELL_FAILED_ANOTHER_IN_PROGRESS = 260,
  SPELL_FAILED_EQUIPPED_SPECIFIC_ITEM = 328, OUT_OF_MANA = 336, OUT_OF_RAGE = 337, OUT_OF_FOCUS = 338,
  OUT_OF_ENERGY = 339, OUT_OF_CHI = 340, OUT_OF_HEALTH = 341, OUT_OF_RUNES = 342, OUT_OF_RUNIC_POWER = 343,
  OUT_OF_SOUL_SHARDS = 344, OUT_OF_LUNAR_POWER = 345, OUT_OF_HOLY_POWER = 346, OUT_OF_MAELSTROM = 347,
  OUT_OF_COMBO_POINTS = 348, OUT_OF_INSANITY = 349, OUT_OF_ARCANE_CHARGES = 350, OUT_OF_FURY = 351, OUT_OF_PAIN = 352,
  OUT_OF_POWER_DISPLAY = 353, SPELL_OUT_OF_RANGE = 369, SPELL_FAILED_NOTUNSHEATHED = 385, SPELL_UNLEARNED_S = 400,
  SPELL_FAILED_ALREADY_AT_FULL_HEALTH = 499, SPELL_FAILED_ALREADY_AT_FULL_MANA = 500,
  SPELL_FAILED_ALREADY_AT_FULL_POWER_S = 501, GENERIC_NO_VALID_TARGETS = 690,
  OUT_OF_ESSENCE = 100001, SPELL_FAILED_CANT_FLY_HERE = 100002, VOICE_CHAT_GENERIC_UNABLE_TO_CONNECT = 100003,
  VOICE_CHAT_SERVICE_LOST = 100004, VOICE_CHAT_CHANNEL_NAME_TOO_SHORT = 100005, VOICE_CHAT_CHANNEL_NAME_TOO_LONG = 100006,
  VOICE_CHAT_CHANNEL_ALREADY_EXISTS = 100007, VOICE_CHAT_TARGET_NOT_FOUND = 100008, VOICE_CHAT_TOO_MANY_REQUESTS = 100009,
  VOICE_CHAT_PLAYER_SILENCED = 100010, VOICE_CHAT_PARENTAL_DISABLE_ALL = 100011, VOICE_CHAT_DISABLED = 100012,
}

-- source: confirmed (rows G21) Blizzard passes the same slot as "HEADSLOT" (blizzard_transmogshared.lua) and "MainHandSlot"
-- (securetemplates.lua:464) to C_PaperDollInfo.GetInventorySlotInfo, so the lookup ignores case.
local INVENTORY_SLOT_INFO = {}
for name, info in pairs(INVENTORY_SLOTS) do
  INVENTORY_SLOT_INFO[name:lower()] = info
end

-- source: assumed (row G21) the engine's LE_EXPANSION_* values (classic 0 up to mists 4) and the expansion level each classic
-- flavor runs at; retail and forever are not modelled here (their LE_EXPANSION_* come from the client dump, row G35).
local EXPANSIONS = {
  LE_EXPANSION_CLASSIC = 0,
  LE_EXPANSION_BURNING_CRUSADE = 1,
  LE_EXPANSION_WRATH_OF_THE_LICH_KING = 2,
  LE_EXPANSION_CATACLYSM = 3,
  LE_EXPANSION_MISTS_OF_PANDARIA = 4,
}
local EXPANSION_LEVEL = { vanilla = 0, tbc = 1, mists = 4 }
-- source: confirmed (row G58) the caps 60/70/80/85 by LE_EXPANSION_* (tbc 70577 blizzard_framexmlbase/cata/constants.lua:10-14,
-- which comments out mists' 90); assumed 90 for mists, and that each classic client's latest expansion is its own.
local MAX_LEVEL_BY_EXPANSION = { [0] = 60, 70, 80, 85, 90 }

-- source: confirmed (row G21) paperdollframe.lua:617 reads _G["SPELL_STAT" .. statIndex .. "_NAME"] with statIndex =
-- LE_UNIT_STAT_*; the strings name SPELL_STAT1..5 Strength, Agility, Stamina, Intellect, Spirit.
local UNIT_STATS = {
  LE_UNIT_STAT_STRENGTH = 1,
  LE_UNIT_STAT_AGILITY = 2,
  LE_UNIT_STAT_STAMINA = 3,
  LE_UNIT_STAT_INTELLECT = 4,
  LE_UNIT_STAT_SPIRIT = 5,
}

-- Legacy quality name -> the Enum.ItemQuality member it equals on the classic family, the only Blizzard Lua that reads them
-- (tbc extract: blizzard_uiparent/<flavor>/uiparent.lua:24-28, blizzard_framexmlbase/<flavor>/constants.lua, ...).
-- source: confirmed (row G26) the values, each flavor's Enum.ItemQuality and ItemQualityMeta.NumValues
-- (api/<flavor>/ItemQualities.lua); assumed the alias set, by the wiki's Enum.ItemQuality 9.0.1 note "Renamed Standard,
-- Good, Superior fields to Common, Uncommon, Rare".
local LEGACY_QUALITIES = {
  LE_ITEM_QUALITY_POOR = "Poor",
  LE_ITEM_QUALITY_COMMON = "Standard",
  LE_ITEM_QUALITY_UNCOMMON = "Good",
  LE_ITEM_QUALITY_RARE = "Rare",
  LE_ITEM_QUALITY_EPIC = "Epic",
  LE_ITEM_QUALITY_LEGENDARY = "Legendary",
  LE_ITEM_QUALITY_ARTIFACT = "Artifact",
  LE_ITEM_QUALITY_HEIRLOOM = "Heirloom",
  LE_ITEM_QUALITY_WOW_TOKEN = "WoWToken",
}
local CLASSIC_FAMILY = { "vanilla", "tbc", "mists" }

-- invSlot, slotTexture, checkRelic of a slot name; nothing for an unknown name.
-- source: confirmed (row G21) the three returns (api/retail/PaperDollInfo.lua; the classic paperdollframe.lua:1292
-- reads `id, textureName, checkRelic` from the global); assumed checkRelic false (no relic slot is modelled).
-- source: confirmed (row G46) the mainline family's bag slots: forever 70862 constants.lua:173 CONTAINER_BAG_OFFSET = 30
-- ("Used for PutItemInBag"; equipmentmanager.lua:183 PutItemInBag(bag + CONTAINER_BAG_OFFSET)), so containers 1-4 and the
-- reagent bag 5 are slots 31-35. assumed: retail the same, no empty-slot texture. The classic flavors keep no bag slots.
local MAINLINE_BAG_SLOTS = { bag0slot = 31, bag1slot = 32, bag2slot = 33, bag3slot = 34, reagentbag0slot = 35 }
local MAINLINE = { retail = true, forever = true }

local function inventorySlotInfo(w, slotName)
  if type(slotName) ~= "string" then
    return
  end
  local bagSlot = MAINLINE[w.flavor] and MAINLINE_BAG_SLOTS[slotName:lower()]
  if bagSlot then
    return bagSlot, nil, false
  end
  local info = INVENTORY_SLOT_INFO[slotName:lower()]
  if not info then
    return
  end

  return info[1], info[2], false
end

-- Get<Type>Metatable name -> the widget type whose class metatable it answers.
local METATABLES = {
  GetFrameMetatable = "Frame",
  GetButtonMetatable = "Button",
  GetEditBoxMetatable = "EditBox",
  GetFontStringMetatable = "FontString",
  -- row G55: forever's api lists it (UnitFrameUtil.lua:129 copies its __index at load).
  GetTextureMetatable = "Texture",
}

function M.install(w)
  -- source: assumed (row G21) the environment of the calling code is the _G addon code sees.
  define(w, "GetCurrentEnvironment", function()
    return AddonEnv.global(w, "_G")
  end)
  -- source: assumed (row G21) the metatable is the one the kit's widgets of that type share ({ __index = methods }).
  for name, typeName in pairs(METATABLES) do
    define(w, name, function()
      return w.ui.classFor(w, typeName).meta
    end)
  end
  -- source: confirmed (row G21) the classic flavors list the global (api/<flavor>/globals.lua) and call it where retail
  -- calls C_PaperDollInfo's (tbc securetemplates.lua:457-460); define installs each name only where the flavor has it.
  for _, name in ipairs({ "C_PaperDollInfo.GetInventorySlotInfo", "GetInventorySlotInfo" }) do
    define(w, name, function(slotName)
      return inventorySlotInfo(w, slotName)
    end)
  end
  for name, value in pairs(UNIT_STATS) do
    define(w, name, value, State.ALL)
  end
  local level = EXPANSION_LEVEL[w.flavor]
  if level then
    for name, value in pairs(EXPANSIONS) do
      define(w, name, value, State.ALL)
    end
    define(w, "GetClassicExpansionLevel", function()
      return level
    end)
    define(w, "ClassicExpansionAtLeast", function(expansionLevel)
      return level >= expansionLevel
    end)
    -- GameRulesUtil.GetEffectiveMaxLevelForPlayer (tbc gamerulesutil.lua:189-193) takes math.min of these.
    for _, name in ipairs({ "GetMaxPlayerLevel", "GetMaxLevelForPlayerExpansion", "GetMaxLevelForLatestExpansion" }) do
      define(w, name, function()
        return MAX_LEVEL_BY_EXPANSION[level]
      end)
    end
  end
  -- source: assumed (row G21) Kiosk is an engine table; Blizzard_MicroMenu asks Kiosk.IsEnabled() on every open, false is a normal client
  define(w, "Kiosk.IsEnabled", function()
    return false
  end, State.ALL)
  -- source: confirmed (row G21) ClassInfo is className, classFile, classID (api/retail/CreatureInfo.lua); assumed the ids and
  -- names are the kit's retail class list (the same order UnitClass's classID follows).
  define(w, "C_CreatureInfo.GetClassInfo", function(classID)
    local classFile = Roster.CLASSES.retail[classID]
    if classFile then
      return { className = Roster.CLASS_NAMES[classFile], classFile = classFile, classID = classID }
    end
  end)
  -- source: confirmed (row G34) the classic flavors fill LOCALIZED_CLASS_NAMES_MALE/FEMALE with it (tbc constants.lua:43-46);
  -- assumed it fills every class token the kit names, and the enUS female names equal the male ones.
  define(w, "FillLocalizedClassList", function(classTable)
    for classFile, name in pairs(Roster.CLASS_NAMES) do
      classTable[classFile] = name
    end
    return classTable
  end)
  -- source: confirmed (row G38) an array of application ids: tbc QueueStatusFrame.lua:119-121 takes its length and passes
  -- each entry to GetApplicationInfo; no API doc types it. assumed: empty, since the kit lists no groups.
  define(w, "C_LFGList.GetApplications", function()
    return {}
  end)
  -- source: confirmed (row G39) it replaces MAX_BATTLEFIELD_QUEUES (wiki), which tbc minimap.lua:13 sets to 3 and :376
  -- falls back to; assumed 3 on every flavor.
  define(w, "GetMaxBattlefieldID", function()
    return 3
  end)
  -- source: confirmed (row G42) a count: tbc QuestLogFrame.lua:671 loops to it and :549 compares it with
  -- MAX_WATCHABLE_QUESTS; no API doc types it. assumed: 0, since the kit tracks no quests.
  define(w, "GetNumQuestWatches", function()
    return 0
  end)
  -- source: confirmed (row G44) the returns base, total, bonus, minus: tbc paperdollframe.lua:486 and wiki API_UnitResistance;
  -- no API doc types it. assumed: all 0, as the kit models no gear or auras that resist.
  define(w, "UnitResistance", function()
    return 0, 0, 0, 0
  end)
  -- source: confirmed (row G44) the returns name, texture, offset, numSlots, isGuild, offSpecID, shouldHide, specID: tbc
  -- spellbookframe.lua:473, :513 and wiki API_GetSpellTabInfo. assumed: two empty tabs, General then the player's class,
  -- since the classic spellbook opens on tab 2 (:414) and the kit models no spellbook.
  define(w, "GetNumSpellTabs", function()
    return 2
  end)
  define(w, "GetSpellTabInfo", function(tabIndex)
    local name
    if tabIndex == 1 then
      name = rawget(_G, "GENERAL") or "General"
    elseif tabIndex == 2 then
      name = _G.UnitClass("player")
    else
      return nil
    end
    return name, nil, 0, 0, false, 0, false, 0
  end)
  define(w, "IsCommunitiesUIDisabledByTrialAccount", function()
    return false
  end, State.ALL)
  -- source: assumed (row BU10) no installed data lists the members of Enum.GameRule, so none is invented: the table is empty,
  -- Enum.GameRule.<Name> is nil and C_GameRules.IsGameRuleActive(nil) answers nothing, i.e. no rule is active. Every
  -- flavor's GameRules doc types values as GameRule, and the classic Lua reads it too.
  if w.manifest.enums.GameRule == nil then
    define(w, "Enum.GameRule", {}, State.ALL)
  end
  -- source: confirmed (row G43) forever blizzard_worldmap.lua:376-378 reads "UNKNOWN" (or nil) as "the rule sets no strata"
  -- and passes any other answer to SetFrameStrata; assumed "UNKNOWN" for every rule, as no rule is active (BU10).
  define(w, "C_GameRules.GetGameRuleAsFrameStrata", function()
    return "UNKNOWN"
  end)
  -- source: confirmed (row G28) the members of Ketho's retail LuaEnum dump; no API doc lists Enum.GameMode, but every
  -- flavor's GameRules doc types values as GameMode; assumed the same members off retail.
  if w.manifest.enums.GameMode == nil then
    define(w, "Enum.GameMode", { Standard = 1, Plunderstorm = 2, WoWHack = 3 }, State.ALL)
  end
  -- source: confirmed (row G27) eventutil.lua:12 asserts it on every event ContinueAfterAllEvents waits for; assumed
  -- valid means an event the flavor's data lists, the set RegisterEvent accepts (world_events.lua checkEvent).
  define(w, "C_EventUtils.IsEventValid", function(event)
    return w:knowsEvent(event)
  end)
  local qualities, meta = w.manifest.enums.ItemQuality or {}, w.manifest.enums.ItemQualityMeta or {}
  for name, member in pairs(LEGACY_QUALITIES) do
    if qualities[member] then
      define(w, name, qualities[member], CLASSIC_FAMILY)
    end
  end
  if meta.NumValues then
    define(w, "NUM_LE_ITEM_QUALITYS", meta.NumValues, CLASSIC_FAMILY)
  end
  for suffix, value in pairs(GAME_ERRORS) do
    local name = "LE_GAME_ERR_" .. suffix
    if rawget(_G, name) == nil then
      w:set(name, value)
    end
  end
  define(w, "C_CurveUtil.CreateCurve", Curve.new)
  -- source: assumed (row G21) the default colour is the colour: the kit keeps no colour overrides.
  for _, name in ipairs({ "C_ColorOverrides.GetColorForQuality", "C_ColorOverrides.GetDefaultColorForQuality" }) do
    define(w, name, qualityColor)
  end
end

return M
