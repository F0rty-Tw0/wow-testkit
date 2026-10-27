-- Global strings addons format tooltip lines with. Kit-authored English test values, not Blizzard's text.
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
}

function M.install(w)
  for name, value in pairs(M.STRINGS) do
    w:install(name, value, GATE)
  end
end

return M
