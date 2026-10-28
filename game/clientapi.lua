-- Client APIs that Blizzard's own UI code calls while it loads and the other game modules do not own. Each one is here
-- because a real-extract run of the Blizzard UI layer (blizzard_ui.lua) stopped on it.
local M = {}

local AddonEnv = require("addon_env")
local Curve = require("game.curve")
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
  define(w, "C_CurveUtil.CreateCurve", Curve.new)
  define(w, "C_ColorOverrides.GetColorForQuality", function(quality)
    return color(QUALITY_COLORS[quality] or QUALITY_COLORS[1])
  end)
end

return M
