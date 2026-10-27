-- Retail secret values: the restrictions (Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat), the secret returns of the kit's
-- implementations for addon callers, the secrecy predicates and the readers. Secret.make, is, reveal and text are
-- combat_secret_value.lua's (the snapshot and the renderer load that file alone). Secret.install (retail only) sets w.isSecret,
-- w.realType and w.returnFilter, which world_api.wrap runs on a kit implementation's results for addon callers.
local M = {}

local Combat = require("combat")
local State = require("game.state")
local Value = require("combat_secret_value")
local define = State.define

-- Localized: addon code may assign a global named select.
local select = select

M.make, M.is, M.reveal, M.text = Value.make, Value.is, Value.reveal, Value.text

local EVENT = "ADDON_RESTRICTION_STATE_CHANGED"

-- source: confirmed (Enum.AddOnRestrictionType, Enum.AddOnRestrictionState; plan Task 8.9).
local TYPES = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
local TYPE_LIST = "ChallengeMode, Chat, Combat, Encounter, Map, PvPMatch"
local INACTIVE, ACTIVATING, ACTIVE = 0, 1, 2

-- source: assumed (row C16) these four restrictions hide what a "returns = always" function gives and what most "when" conditions
-- name; no source says which restrictions a kit state has.
local SECRET_RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }
local NO_RESTRICTIONS = {}
local CONDITION_RESTRICTIONS = {
  InCombat = { "Combat" },
  ActivePvPMatch = { "PvPMatch" },
  EncounterEvent = { "Encounter" },
  ChatMessagingLockdown = { "Chat" },
}
-- source: assumed (row C17) the combat log payload after the subevent is secret while the log is restricted.
local LOG_ACCESSORS = { CombatLogGetCurrentEventInfo = true, ["C_CombatLog.GetCurrentEventInfo"] = true }
local FIRST_SECRET_LOG_FIELD = 3
local PREDICATE = "^C_Secrets%.Should.*BeSecret$"

-- Restrictions ------------------------------------------------------------------------------------------------------------

local function isActive(w, name)
  return w.mock.restrictions[TYPES[name]] == ACTIVE
end

local function anyActive(w, names)
  for _, name in ipairs(names) do
    if isActive(w, name) then
      return true
    end
  end
  return false
end

-- Turns a restriction on or off. On: the state is Activating and then Active, each fired as ADDON_RESTRICTION_STATE_CHANGED(type,
-- state); off: Inactive. source: assumed (row C16, plan) the order of the two states and that nothing fires without a change.
function M.setRestriction(w, name, on)
  local kind = TYPES[name]
  if not kind then
    error(string.format("Secret.setRestriction: unknown restriction '%s'; valid: %s", tostring(name), TYPE_LIST), 2)
  end
  if isActive(w, name) == on then
    return
  end
  for _, state in ipairs(on and { ACTIVATING, ACTIVE } or { INACTIVE }) do
    w:setMock({ restrictions = { [kind] = state } })
    Combat.fire(w, EVENT, kind, state)
  end
end

local function bossEngaged(w)
  for _, actor in pairs(w.combat.actors) do
    if actor.kind == "boss" and actor.affectingCombat then
      return true
    end
  end
  return false
end

-- Combat follows the player's lockdown (State's "lockdown" hook), Encounter a boss actor being engaged ("flags").
function M.sync(w)
  M.setRestriction(w, "Combat", w.mock.combat == true)
  M.setRestriction(w, "Encounter", bossEngaged(w))
end

-- The restrictions a "when" condition names: the ones listed above, and every other *Restricted condition gets the four
-- secret restrictions. Conditions about arguments (AnchoringSecret, CurveSecret, ...) name none.
local function restrictionsOf(condition)
  if CONDITION_RESTRICTIONS[condition] then
    return CONDITION_RESTRICTIONS[condition]
  end
  return condition:match("Restricted$") and SECRET_RESTRICTIONS or NO_RESTRICTIONS
end

local function shouldBeSecret(w, secret)
  if secret.returns == "always" then
    return anyActive(w, SECRET_RESTRICTIONS)
  elseif secret.returns ~= "when" then
    return false
  end
  for _, condition in ipairs(secret.when or NO_RESTRICTIONS) do
    if anyActive(w, restrictionsOf(condition)) then
      return true
    end
  end
  return false
end

local function hide(w, packed, from)
  local out = { n = packed.n }
  for i = 1, packed.n do
    local value = packed[i]
    out[i] = (i >= from and value ~= nil) and M.make(value, w) or value
  end
  return out
end

-- w.returnFilter: the packed results of a kit implementation for an addon caller, secret where the manifest's secret field says so.
function M.filter(w)
  return function(name, signature, packed)
    if LOG_ACCESSORS[name] then
      return anyActive(w, SECRET_RESTRICTIONS) and hide(w, packed, FIRST_SECRET_LOG_FIELD) or packed
    end
    local secret = signature and signature.secret
    return secret and shouldBeSecret(w, secret) and hide(w, packed, 1) or packed
  end
end

local function installPredicates(w)
  local restricted = function()
    return anyActive(w, SECRET_RESTRICTIONS)
  end
  for name in pairs(w.manifest.functions) do
    if name:match(PREDICATE) then
      define(w, name, restricted)
    end
  end
  -- source: confirmed (row C16) true on a client build with restrictions; assumed that the kit's retail world is one.
  define(w, "C_Secrets.HasSecretRestrictions", function()
    return true
  end)
  -- source: assumed (row C17) restricted while the secret restrictions are.
  define(w, "C_CombatLog.IsCombatLogRestricted", restricted)
  define(w, "C_RestrictedActions.GetAddOnRestrictionState", function(kind)
    return w.mock.restrictions[kind] or INACTIVE
  end)
end

local function installReaders(w)
  define(w, "canaccessvalue", function(value)
    return Value.accessible(value)
  end)
  define(w, "hasanysecretvalues", function(...)
    for i = 1, select("#", ...) do
      if M.is((select(i, ...))) then
        return true
      end
    end
    return false
  end)
end

-- The type argument validation sees: a secret has the type of the value it hides.
local function realType(value)
  return type(M.reveal(value))
end

-- Retail only: every other flavor's world keeps w.isSecret and w.returnFilter unset, so nothing there is ever secret.
function M.install(w)
  if w.flavor ~= "retail" then
    return
  end
  w.isSecret = M.is
  w.returnFilter = M.filter(w)
  w.realType = realType
  installReaders(w)
  installPredicates(w)
  local function sync()
    M.sync(w)
  end
  Combat.listen(w, "lockdown", sync)
  Combat.listen(w, "flags", sync)
end

return M
