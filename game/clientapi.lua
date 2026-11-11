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

-- source: confirmed (rows G21) Blizzard passes the same slot as "HEADSLOT" (blizzard_transmogshared.lua) and "MainHandSlot"
-- (securetemplates.lua:464) to C_PaperDollInfo.GetInventorySlotInfo, so the lookup ignores case.
local INVENTORY_SLOT_INFO = {}
for name, info in pairs(INVENTORY_SLOTS) do
  INVENTORY_SLOT_INFO[name:lower()] = info
end

-- source: assumed (row G21) the engine's LE_EXPANSION_* values (classic 0 up to mists 4) and the expansion level each classic
-- flavor runs at; retail and forever are not modelled.
local EXPANSIONS = {
  LE_EXPANSION_CLASSIC = 0,
  LE_EXPANSION_BURNING_CRUSADE = 1,
  LE_EXPANSION_WRATH_OF_THE_LICH_KING = 2,
  LE_EXPANSION_CATACLYSM = 3,
  LE_EXPANSION_MISTS_OF_PANDARIA = 4,
}
local EXPANSION_LEVEL = { vanilla = 0, tbc = 1, mists = 4 }

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
local function inventorySlotInfo(slotName)
  if type(slotName) ~= "string" then
    return
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
    define(w, name, inventorySlotInfo)
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
  define(w, "IsCommunitiesUIDisabledByTrialAccount", function()
    return false
  end, State.ALL)
  -- source: assumed (row BU10) no installed data lists the members of Enum.GameRule, so none is invented: the table is empty,
  -- Enum.GameRule.<Name> is nil and C_GameRules.IsGameRuleActive(nil) answers nothing, i.e. no rule is active. Every
  -- flavor's GameRules doc types values as GameRule, and the classic Lua reads it too.
  if w.manifest.enums.GameRule == nil then
    define(w, "Enum.GameRule", {}, State.ALL)
  end
  -- source: confirmed (row G28) the members of Ketho's retail LuaEnum dump; no API doc lists Enum.GameMode, but every
  -- flavor's GameRules doc types values as GameMode; assumed the same members off retail.
  if w.manifest.enums.GameMode == nil then
    define(w, "Enum.GameMode", { Standard = 1, Plunderstorm = 2, WoWHack = 3 }, State.ALL)
  end
  -- source: assumed (row G30) two distinct store front ids: an engine constant no API doc or dump lists, read only as
  -- table keys and C_AccountStore arguments (retail gamerulesutil.lua:41-44, blizzard_accountstore.lua:4).
  if w.manifest.constants.AccountStoreConsts == nil then
    define(w, "Constants.AccountStoreConsts", { PlunderstormStoreFrontID = 1, WowhackStoreFrontID = 2 }, State.ALL)
  end
  -- source: confirmed (row G27) eventutil.lua:12 asserts it on every event ContinueAfterAllEvents waits for; assumed
  -- valid means an event the flavor's data lists, the set RegisterEvent accepts (world_events.lua checkEvent).
  define(w, "C_EventUtils.IsEventValid", function(event)
    return (w.manifest.events[event] or w.globals.events[event]) ~= nil
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
  define(w, "C_CurveUtil.CreateCurve", Curve.new)
  -- source: assumed (row G21) the default colour is the colour: the kit keeps no colour overrides.
  for _, name in ipairs({ "C_ColorOverrides.GetColorForQuality", "C_ColorOverrides.GetDefaultColorForQuality" }) do
    define(w, name, qualityColor)
  end
end

return M
