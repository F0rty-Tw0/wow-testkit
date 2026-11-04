-- Global strings addons format tooltip lines with. Kit-authored English test values, except the spell failure texts at the
-- end, which are the retail extract's.
local M = {}

local GATE = { gate = "none" }

M.STRINGS = {
  TOOLTIP_UNIT_LEVEL = "Level %s",
  TOOLTIP_UNIT_LEVEL_CLASS = "Level %s %s",
  TOOLTIP_UNIT_LEVEL_RACE_CLASS = "Level %s %s %s",
  FACTION_ALLIANCE = "Alliance",
  FACTION_HORDE = "Horde",
  PVP = "PvP",
  ITEM_LEVEL = "Item Level %d",
  ACCEPT = "Accept",
  CANCEL = "Cancel",
  OKAY = "Okay",
  YES = "Yes",
  NO = "No",
  GOLD = "Gold",
  SILVER = "Silver",
  COPPER = "Copper",
  GOLD_AMOUNT = "%d Gold",
  SILVER_AMOUNT = "%d Silver",
  COPPER_AMOUNT = "%d Copper",
  LARGE_NUMBER_SEPERATOR = ",",
  ERR_LOOT_TOO_FAR = "Too far away to loot",
  ERR_INV_FULL = "Bags are full",
  LOOT_ITEM_SELF = "You loot: %s",
  LOOT_ITEM_SELF_MULTIPLE = "You loot: %sx%d",
  YOU_LOOT_MONEY = "You loot %s",
  ERR_BADATTACKPOS = "Target is out of melee range",
  ERR_BADATTACKFACING = "You are not facing the target",
  -- source: confirmed (the retail extract's strings/enUS.lua, builds 70575 and 70688) the spell cast failure texts.
  ERR_OUT_OF_MANA = "Not enough mana",
  ERR_OUT_OF_RAGE = "Not enough rage",
  SPELL_FAILED_BAD_IMPLICIT_TARGETS = "No target",
  SPELL_FAILED_MOVING = "Can't do that while moving",
  SPELL_FAILED_NOT_READY = "Not yet recovered",
  SPELL_FAILED_OUT_OF_RANGE = "Out of range",
  SPELL_FAILED_SPELL_IN_PROGRESS = "Another action is in progress",
  SPELL_FAILED_STUNNED = "Can't do that while stunned",
  SPELL_FAILED_TOO_CLOSE = "Target too close",
  SPELL_FAILED_UNIT_NOT_INFRONT = "Target needs to be in front of you.",
}

function M.install(w)
  for name, value in pairs(M.STRINGS) do
    w:install(name, value, GATE)
  end
end

return M
