-- Unit fixtures: w:unit(token, data) registers what the Unit* APIs answer for a unit token, w:mouseover(token)
-- points "mouseover" at a registered unit. Answers are installed as kit implementations, so validation, call
-- counting and w:stub overrides still apply, and names the flavor lacks are skipped.
local M = {}

local WorldApi = require("world_api")

local unpack = unpack

local MOUSEOVER = "mouseover"
local PLAYER_GUID = "Player-0000-%d"
local CREATURE_GUID = "Creature-0-0-0-0-%d"
local GUILD_RANK_INDEX = 0
local API_GATE = { gate = "api" }
local MYTHIC_SUMMARY = "C_PlayerInfo.GetPlayerMythicPlusRatingSummary"
-- wiki API_UnitTokenFromGUID's test order; "#" marks a numbered group (party1, party2, ...).
local TOKEN_ORDER = {
  "player",
  "vehicle",
  "pet",
  "party#",
  "partypet#",
  "raid#",
  "raidpet#",
  "nameplate#",
  "arena#",
  "arenapet#",
  "boss#",
  "target",
  "focus",
  "npc",
  "mouseover",
  "softenemy",
  "softfriend",
  "softinteract",
}
-- Rank step per TOKEN_ORDER entry; above any unit index.
local INDEX_SPAN = 1000

-- API name -> the fixture fields it returns, in return order.
local FIELD_ANSWERS = {
  UnitName = { "name", "realm" },
  UnitClass = { "className", "classFile" },
  UnitRace = { "raceName", "raceFile" },
  UnitLevel = { "level" },
  UnitEffectiveLevel = { "effectiveLevel" },
  UnitIsPlayer = { "isPlayer" },
  UnitReaction = { "reaction" },
  UnitFactionGroup = { "faction", "faction" },
  UnitHealth = { "health" },
  UnitHealthMax = { "healthMax" },
  UnitPower = { "power" },
  UnitPowerMax = { "powerMax" },
  UnitIsFriend = { "isFriend" },
  UnitInParty = { "inParty" },
  UnitInRaid = { "inRaid" },
  UnitIsPVP = { "pvp" },
}

-- Fields that answer nil when unset instead of the manifest default (UnitName's realm is nil for same-realm units).
local NIL_WHEN_UNSET = { realm = true }

-- Field -> the field it falls back to when unset (an unscaled unit's effective level is its level).
local FALLBACK_FIELD = { effectiveLevel = "level" }

-- Unit tokens are case-insensitive in the client; non-strings (unvalidated calls) pass through and match nothing.
local function normalize(token)
  return type(token) == "string" and token:lower() or token
end

-- The fixture for a token ("mouseover" follows the alias) and the token it resolved to.
local function fixture(state, token)
  token = normalize(token)
  if token == MOUSEOVER and state.alias then
    token = state.alias
  end
  return state.byToken[token], token
end

local function guidOf(state, token)
  local data, resolved = fixture(state, token)
  return data and (data.guid or state.guids[resolved])
end

local function fieldAnswer(w, name, fields)
  local signature = w.manifest.functions[name]
  local defaults = signature and WorldApi.defaults(signature) or { n = 0 }
  return function(unit)
    local data = fixture(w.unitState, unit)
    if not data then
      WorldApi.markUnscripted(w, name)
      return unpack(defaults, 1, defaults.n)
    end
    local out, defaulted = {}, false
    for i, field in ipairs(fields) do
      local value = data[field]
      if value == nil and FALLBACK_FIELD[field] then
        value = data[FALLBACK_FIELD[field]]
      end
      if value == nil and not NIL_WHEN_UNSET[field] then
        value, defaulted = defaults[i], true
      end
      out[i] = value
    end
    if defaulted then
      WorldApi.markUnscripted(w, name)
    end
    return unpack(out, 1, #fields)
  end
end

-- The token's place in TOKEN_ORDER (a numbered group ordered by its index), or nil for a token the client never tests.
local function tokenRank(token)
  for i, entry in ipairs(TOKEN_ORDER) do
    local group = entry:match("^(%a+)#$")
    local index = group and tonumber(token:match("^" .. group .. "([1-9]%d*)$"))
    if token == entry or index then
      return i * INDEX_SPAN + (index or 0)
    end
  end

  return nil
end

-- source: wiki API_UnitTokenFromGUID, "Unit tokens will be tested in the order given below, returning the first one
-- that matches". "mouseover" is a candidate whenever it resolves, through a fixture or the w:mouseover alias.
local function tokenFromGuid(state, guid)
  local ranks = { [MOUSEOVER] = tokenRank(MOUSEOVER) }
  for token in pairs(state.byToken) do
    ranks[token] = tokenRank(token)
  end
  local tokens = {}
  for token in pairs(ranks) do
    tokens[#tokens + 1] = token
  end
  table.sort(tokens, function(a, b)
    return ranks[a] < ranks[b]
  end)
  for _, token in ipairs(tokens) do
    if guidOf(state, token) == guid then
      return token
    end
  end
  return nil
end

-- Identity answers (UnitExists, UnitIsUnit, UnitGUID, UnitTokenFromGUID) are always scripted: a missing fixture
-- means "no such unit". Guild and mythic answers count as unscripted when their field is unset.
local function specialAnswers(w)
  local state = w.unitState
  return {
    UnitExists = function(unit)
      return fixture(state, unit) ~= nil
    end,
    UnitIsUnit = function(a, b)
      local guid = guidOf(state, a)
      return guid ~= nil and guid == guidOf(state, b)
    end,
    UnitGUID = function(unit)
      return guidOf(state, unit)
    end,
    UnitTokenFromGUID = function(guid)
      return tokenFromGuid(state, guid)
    end,
    GetGuildInfo = function(unit)
      local data = fixture(state, unit)
      if data and data.guild then
        return data.guild, data.guildRank, GUILD_RANK_INDEX
      end
      WorldApi.markUnscripted(w, "GetGuildInfo")
    end,
    [MYTHIC_SUMMARY] = function(unit)
      local data = fixture(state, unit)
      if data and data.mythicScore then
        return { currentSeasonScore = data.mythicScore }
      end
      WorldApi.markUnscripted(w, MYTHIC_SUMMARY)
      return nil
    end,
  }
end

-- Registers or replaces token's fixture; data nil removes it. Unset guids are generated per registration.
local function unit(self, token, data)
  if type(token) ~= "string" then
    error("w:unit: token must be a string, got " .. type(token), 2)
  end
  if data ~= nil and type(data) ~= "table" then
    error("w:unit: data must be a table or nil, got " .. type(data), 2)
  end
  token = normalize(token)
  local state = self.unitState
  state.count = state.count + 1
  state.byToken[token] = data
  state.guids[token] = data and string.format(data.isPlayer and PLAYER_GUID or CREATURE_GUID, state.count)
end

-- Makes "mouseover" answer as token's fixture; nil clears it.
local function mouseover(self, token)
  self.unitState.alias = normalize(token)
end

function M.install(w)
  w.unitState = { byToken = {}, guids = {}, alias = nil, count = 0 }
  w.unit = unit
  w.mouseover = mouseover
  for name, fields in pairs(FIELD_ANSWERS) do
    w:install(name, fieldAnswer(w, name, fields), API_GATE)
  end
  for name, answer in pairs(specialAnswers(w)) do
    w:install(name, answer, API_GATE)
  end
end

return M
