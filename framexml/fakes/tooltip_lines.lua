-- A unit's tooltip data, shaped like the client's tooltip info for GameTooltip:SetUnit: one entry per line
-- (name, guild, level, faction, PvP), built from the unit's fixture answers (Unit* APIs asked under "blizzard"
-- context) and the FrameXML strings and colors. Colors are { r, g, b } keyed tables.
local M = {}

local UNKNOWN_LEVEL = -1
local UNKNOWN_LEVEL_TEXT = "??"
local DEFAULT_CHANNEL = 1
local FACTION_PREFIX = "FACTION_"
local GUILD_FORMAT = "<%s>"
local REACTION_TARGET = "player"
local FALLBACK_LINE_TYPE = "None"
-- Line -> Enum.TooltipDataLineType key, resolved at runtime; a key the flavor's enum lacks falls back to None.
-- level = None: MouseOverTooltip Tooltip/LineFilter.lua (written against the live client) sees the level line
-- among None lines; Enum.TooltipDataLineType.UnitLevel exists but is not used for it — verify in game.
local LINE_TYPES = { name = "UnitName", level = "None", guild = "None", faction = "None", pvp = "None" }

-- Calls the API name under "blizzard" context; nothing when the flavor lacks it.
function M.ask(w, name, ...)
  local fn = rawget(_G, name)
  if fn then
    return w:run("blizzard", fn, ...)
  end
end

local function rgb(color)
  if type(color) ~= "table" then
    return { r = DEFAULT_CHANNEL, g = DEFAULT_CHANNEL, b = DEFAULT_CHANNEL }
  end
  return { r = color.r, g = color.g, b = color.b }
end

local function line(kind, text, color)
  local lineTypes = _G.Enum.TooltipDataLineType
  local lineType = lineTypes[LINE_TYPES[kind]] or lineTypes[FALLBACK_LINE_TYPE]
  return { type = lineType, leftText = text, leftColor = rgb(color) }
end

-- Players: class color; NPCs: reaction color; white when either is unknown.
local function nameColor(w, unit, isPlayer)
  if isPlayer then
    local _, classFile = M.ask(w, "UnitClass", unit)
    local colors = rawget(_G, "RAID_CLASS_COLORS")
    return colors and classFile and colors[classFile]
  end
  local reaction = M.ask(w, "UnitReaction", unit, REACTION_TARGET)
  local colors = rawget(_G, "FACTION_BAR_COLORS")
  return colors and reaction and colors[reaction]
end

local function nameText(w, unit)
  local name, realm = M.ask(w, "UnitName", unit)
  if type(realm) == "string" and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

local function levelText(w, unit, isPlayer)
  local level = M.ask(w, "UnitLevel", unit)
  if level == UNKNOWN_LEVEL then
    level = UNKNOWN_LEVEL_TEXT
  end
  if isPlayer then
    local race = M.ask(w, "UnitRace", unit)
    local class = M.ask(w, "UnitClass", unit)
    return string.format(_G.TOOLTIP_UNIT_LEVEL_RACE_CLASS, tostring(level), tostring(race), tostring(class))
  end
  return string.format(_G.TOOLTIP_UNIT_LEVEL, tostring(level))
end

-- The localized faction name (FACTION_HORDE, ...), the raw group when no string exists, nil when unset.
local function factionText(w, unit)
  local faction = M.ask(w, "UnitFactionGroup", unit)
  if type(faction) ~= "string" or faction == "" then
    return nil
  end
  return rawget(_G, FACTION_PREFIX .. faction:upper()) or faction
end

local function addFactionAndPvp(w, unit, lines)
  local faction = factionText(w, unit)
  if faction then
    lines[#lines + 1] = line("faction", faction)
  end
  if M.ask(w, "UnitIsPVP", unit) == true then
    lines[#lines + 1] = line("pvp", _G.PVP)
  end
end

function M.build(w, unit)
  local isPlayer = M.ask(w, "UnitIsPlayer", unit) == true
  local lines = { line("name", nameText(w, unit), nameColor(w, unit, isPlayer)) }
  local guild = isPlayer and M.ask(w, "GetGuildInfo", unit)
  if guild then
    lines[#lines + 1] = line("guild", string.format(GUILD_FORMAT, guild))
  end
  lines[#lines + 1] = line("level", levelText(w, unit, isPlayer))
  addFactionAndPvp(w, unit, lines)
  return { type = _G.Enum.TooltipDataType.Unit, guid = M.ask(w, "UnitGUID", unit), lines = lines }
end

return M
