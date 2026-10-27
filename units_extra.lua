-- Unit answers that are more than one fixture field: full and display names, dead-or-ghost, enemy and attackable
-- flags, cast and channel tuples, and the legacy aura tuples. Units.install hands in its fixture lookup, so this module
-- never requires units.
local M = {}

local State = require("game.state")
local WorldApi = require("world_api")
local define, ALL = State.define, State.ALL

local unpack = unpack

local FOREIGN_SERVER_LABEL = " (*)"
local PLAYER = "player"
-- source: confirmed (row G12) the UnitCastingInfo and UnitChannelInfo returns, in order.
local CAST_FIELDS = {
  "name",
  "displayName",
  "textureID",
  "startTimeMs",
  "endTimeMs",
  "isTradeskill",
  "castID",
  "notInterruptible",
  "castingSpellID",
  "castBarID",
  "delayTimeMs",
}
local CHANNEL_FIELDS = {
  "name",
  "displayName",
  "textureID",
  "startTimeMs",
  "endTimeMs",
  "isTradeskill",
  "notInterruptible",
  "spellID",
  "isEmpowered",
  "numEmpowerStages",
  "castBarID",
}
-- source: confirmed (row G12) UnitAura unpacks these AuraData fields in order, then the points.
local AURA_FIELDS = {
  "name",
  "icon",
  "applications",
  "dispelName",
  "duration",
  "expirationTime",
  "sourceUnit",
  "isStealable",
  "nameplateShowPersonal",
  "spellId",
  "canApplyAura",
  "isBossAura",
  "isFromPlayerOrPlayerPet",
  "nameplateShowAll",
  "timeMod",
}
-- Flavors with Blizzard's UnitAura, UnitBuff and UnitDebuff deprecation fallbacks (row G1).
local CLASSIC_FLAVORS = { "mists", "tbc", "vanilla" }

-- Answers an unknown unit with the API's default and counts it as unscripted.
local function unknownUnit(w, name)
  local signature = w.manifest.functions[name]
  local defaults = signature and WorldApi.defaults(signature) or { n = 0 }
  WorldApi.markUnscripted(w, name)
  return unpack(defaults, 1, defaults.n)
end

-- The fixture's fields in order; trailing nils are kept so the tuple has the API's length.
local function tuple(record, fields, extra)
  local out = {}
  for i, field in ipairs(fields) do
    out[i] = record[field]
  end
  local n = #fields
  for i, value in ipairs(extra or {}) do
    out[n + i] = value
  end
  return unpack(out, 1, n + #(extra or {}))
end

-- source: confirmed (row G10) UnitFullName("player") always carries the player's realm (normalized as
-- GetNormalizedRealmName); assumed another same-realm unit has none.
local function installNames(w, deps)
  local fixture = deps.fixture
  define(w, "UnitFullName", function(unit)
    local data, token = fixture(w.unitState, unit)
    if not data then
      return unknownUnit(w, "UnitFullName")
    end
    local realm = data.realm
    if token == PLAYER and w.mock and w.mock.realm then
      realm = w.mock.realm:gsub("[ %-%.]", "")
    end
    return data.name, realm
  end)
  -- source: confirmed (row G10) Blizzard's GetUnitName (unitframe.lua:1085-1101); assumed the kit's
  -- UnitRealmRelationship never reports a virtual realm, so every fixture realm is foreign.
  define(w, "GetUnitName", function(unit, showServerName)
    local data = fixture(w.unitState, unit)
    if not data then
      return unknownUnit(w, "GetUnitName")
    end
    local realm = data.realm
    if realm == nil or realm == "" then
      return data.name
    elseif showServerName then
      return data.name .. "-" .. realm
    end
    return data.name .. (_G.FOREIGN_SERVER_LABEL or FOREIGN_SERVER_LABEL)
  end, ALL)
end

local function installFlags(w, deps)
  local fixture, fieldAnswer, normalize = deps.fixture, deps.fieldAnswer, deps.normalize
  define(w, "UnitIsDeadOrGhost", function(unit)
    local data = fixture(w.unitState, unit)
    if not data then
      return unknownUnit(w, "UnitIsDeadOrGhost")
    end
    return data.isDead == true or data.isGhost == true
  end)
  -- source: assumed (row G11) the flag is read for ("player", other) only; any other first unit is unscripted.
  for name, field in pairs({ UnitIsEnemy = "isEnemy", UnitCanAttack = "canAttack" }) do
    local read = fieldAnswer(w, name, { field })
    define(w, name, function(unit, target)
      if normalize(unit) == PLAYER then
        return read(target)
      end
      return unknownUnit(w, name)
    end)
  end
end

-- source: assumed (row G12) every return is absent, not only name, when the unit is not casting or channeling.
local function installCasts(w, deps)
  local fixture = deps.fixture
  local function install(name, key, fields)
    define(w, name, function(unit)
      local data = fixture(w.unitState, unit)
      if not data then
        return unknownUnit(w, name)
      elseif data[key] then
        return tuple(data[key], fields)
      end
    end)
  end
  install("UnitCastingInfo", "cast", CAST_FIELDS)
  install("UnitChannelInfo", "channel", CHANNEL_FIELDS)
end

local function isHarmful(aura)
  if aura.isHarmful ~= nil then
    return aura.isHarmful and true or false
  end
  return not aura.isHelpful
end

-- The index-th aura of the wanted kind; index counts within the kind.
local function nthAura(data, index, harmful)
  local seen = 0
  for _, aura in ipairs(data.auras or {}) do
    if isHarmful(aura) == harmful then
      seen = seen + 1
      if seen == index then
        return aura
      end
    end
  end
end

-- source: confirmed (row G1) the fallbacks exist on the classic flavors only; the real ones forward to
-- C_UnitAuras.GetAuraDataByIndex / GetBuffDataByIndex / GetDebuffDataByIndex, which read the same fixture auras.
-- Assumed (row G12) UnitBuff and UnitDebuff add HELPFUL and HARMFUL themselves; UnitAura without a filter reads helpful
-- auras; filter flags other than HELPFUL and HARMFUL are ignored.
local function installAuras(w, deps)
  local fixture = deps.fixture
  local function install(name, harmfulFor)
    define(w, name, function(unit, index, filter)
      local data = fixture(w.unitState, unit)
      if not data then
        return unknownUnit(w, name)
      end
      local aura = type(index) == "number" and nthAura(data, index, harmfulFor(filter))
      if aura then
        return tuple(aura, AURA_FIELDS, aura.points)
      end
    end, CLASSIC_FLAVORS)
  end
  install("UnitAura", function(filter)
    return type(filter) == "string" and filter:upper():find("HARMFUL", 1, true) ~= nil
  end)
  install("UnitBuff", function()
    return false
  end)
  install("UnitDebuff", function()
    return true
  end)
end

-- deps: { fixture = Units' fixture(state, token), fieldAnswer = Units' fieldAnswer(w, name, fields), normalize }.
function M.install(w, deps)
  installNames(w, deps)
  installFlags(w, deps)
  installCasts(w, deps)
  installAuras(w, deps)
end

return M
