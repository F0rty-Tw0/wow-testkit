-- Client APIs that Blizzard's own UI code calls while it loads and the other game modules do not own. Each one is here
-- because a real-extract run of the Blizzard UI layer (blizzard_ui.lua) stopped on it.
local M = {}

local AddonEnv = require("addon_env")
local Curve = require("game.curve")
local Roster = require("combat_roster_data")
local State = require("game.state")
local define = State.define

M.DEFAULTS = {}

-- source: assumed (row G21) the item quality colors by quality 0-8 (poor to wow token), the values of the client's
-- default UI.
local QUALITY_COLORS = {
  [0] = { 0.62, 0.62, 0.62 },
  { 1, 1, 1 },
  { 0.12, 1, 0 },
  { 0, 0.44, 0.87 },
  { 0.64, 0.21, 0.93 },
  { 1, 0.5, 0 },
  { 0.9, 0.8, 0.5 },
  { 0, 0.8, 1 },
  { 0, 0.8, 1 },
}

-- A color table; once Blizzard's ColorMixin exists (Blizzard_SharedXMLBase) the table carries its methods.
local function color(rgb)
  local result = { r = rgb[1], g = rgb[2], b = rgb[3], a = 1 }
  local mixin = rawget(_G, "ColorMixin")
  return type(mixin) == "table" and setmetatable(result, { __index = mixin }) or result
end

-- source: assumed (row G21) the inventory slot ids by slot name (the wiki's InventorySlotId list, from memory).
local INVENTORY_SLOTS = {
  HeadSlot = 1,
  NeckSlot = 2,
  ShoulderSlot = 3,
  ShirtSlot = 4,
  ChestSlot = 5,
  WaistSlot = 6,
  LegsSlot = 7,
  FeetSlot = 8,
  WristSlot = 9,
  HandsSlot = 10,
  Finger0Slot = 11,
  Finger1Slot = 12,
  Trinket0Slot = 13,
  Trinket1Slot = 14,
  BackSlot = 15,
  MainHandSlot = 16,
  SecondaryHandSlot = 17,
  RangedSlot = 18,
  TabardSlot = 19,
}

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
  define(w, "C_PaperDollInfo.GetInventorySlotInfo", function(slotName)
    return INVENTORY_SLOTS[slotName]
  end)
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
  define(w, "IsCommunitiesUIDisabledByTrialAccount", function()
    return false
  end, State.ALL)
  -- source: assumed (row BU10) no installed data lists the members of Enum.GameRule, so none is invented: the table is empty,
  -- Enum.GameRule.<Name> is nil and C_GameRules.IsGameRuleActive(nil) answers nothing, i.e. no rule is active.
  if w.manifest.enums.GameRule == nil then
    define(w, "Enum.GameRule", {}, { "retail", "forever" })
  end
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
  define(w, "C_ColorOverrides.GetColorForQuality", function(quality)
    return color(QUALITY_COLORS[quality] or QUALITY_COLORS[1])
  end)
end

return M
