-- Color globals: class colors, reaction (faction bar) colors, tooltip defaults and difficulty colors.
-- Class colors are the commonly published hex values; difficulty bands are a kit approximation of the client's.
local M = {}

local ColorUtil = require("framexml.fakes.color_util")
local Core = require("framexml.fakes.core")

local HEX_MAX = 255
local DEFAULT_PLAYER_LEVEL = 80
-- Level difference (target - player) at or above which a color applies; below GREEN_MIN_DIFF is grey.
local RED_MIN_DIFF = 5
local ORANGE_MIN_DIFF = 3
local YELLOW_MIN_DIFF = -2
local GREEN_MIN_DIFF = -10
-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }

local CLASS_HEX = {
  WARRIOR = "c69b6d",
  PALADIN = "f48cba",
  HUNTER = "aad372",
  ROGUE = "fff468",
  PRIEST = "ffffff",
  DEATHKNIGHT = "c41e3a",
  SHAMAN = "0070dd",
  MAGE = "3fc7eb",
  WARLOCK = "8788ee",
  MONK = "00ff98",
  DRUID = "ff7c0a",
  DEMONHUNTER = "a330c9",
  EVOKER = "33937f",
}

local function channel(hex, first)
  return tonumber(hex:sub(first, first + 1), 16) / HEX_MAX
end

local function classColors()
  local out = {}
  for class, hex in pairs(CLASS_HEX) do
    local color = ColorUtil.new(channel(hex, 1), channel(hex, 3), channel(hex, 5), 1)
    color.colorStr = "ff" .. hex
    out[class] = color
  end
  return out
end

-- Reactions 1-2 hostile red, 3 unfriendly orange, 4 neutral yellow, 5-8 friendly green.
local function factionBarColors()
  local red, orange = { r = 0.8, g = 0.3, b = 0.22 }, { r = 0.75, g = 0.27, b = 0 }
  local yellow, green = { r = 0.9, g = 0.7, b = 0 }, { r = 0, g = 0.6, b = 0.1 }
  return { red, red, orange, yellow, green, green, green, green }
end

local function difficultyColors()
  return {
    impossible = { r = 1, g = 0.1, b = 0.1 },
    veryDifficult = { r = 1, g = 0.5, b = 0.25 },
    difficult = { r = 1, g = 0.82, b = 0 },
    standard = { r = 0.25, g = 0.75, b = 0.25 },
    trivial = { r = 0.5, g = 0.5, b = 0.5 },
  }
end

-- The player's level as FrameXML reads it (UnitLevel under "blizzard" context); DEFAULT_PLAYER_LEVEL when unset.
local function playerLevel(w)
  local unitLevel = rawget(_G, "UnitLevel")
  local level = unitLevel and w:run("blizzard", unitLevel, "player")
  if type(level) ~= "number" or level <= 0 then
    return DEFAULT_PLAYER_LEVEL
  end
  return level
end

local function difficultyColor(w, colors)
  return function(level)
    local diff = (tonumber(level) or 0) - playerLevel(w)
    if diff >= RED_MIN_DIFF then
      return colors.impossible
    elseif diff >= ORANGE_MIN_DIFF then
      return colors.veryDifficult
    elseif diff >= YELLOW_MIN_DIFF then
      return colors.difficult
    elseif diff >= GREEN_MIN_DIFF then
      return colors.standard
    end
    return colors.trivial
  end
end

function M.install(w)
  w:install("RAID_CLASS_COLORS", classColors(), Core.GATE)
  w:install("FACTION_BAR_COLORS", factionBarColors(), Core.GATE)
  w:install("TOOLTIP_DEFAULT_COLOR", { r = 1, g = 1, b = 1 }, Core.GATE)
  w:install("TOOLTIP_DEFAULT_BACKGROUND_COLOR", { r = 0.09, g = 0.09, b = 0.19 }, Core.GATE)
  local byLevel = difficultyColor(w, difficultyColors())
  for _, name in ipairs({ "GetQuestDifficultyColor", "GetCreatureDifficultyColor", "GetDifficultyColor" }) do
    w:install(name, byLevel, KETHO_GATE)
  end
end

return M
