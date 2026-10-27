-- Auras on actors: AuraData tables kept in actor.auras (the list Units' legacy UnitAura reads), expiry on the world
-- clock, the absorb total the UnitGetTotalAbsorbs answer reads, and the C_UnitAuras readers.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local Spells = require("combat_spells")
local State = require("game.state")
local Units = require("units")
local UnitsExtra = require("units_extra")
local WorldApi = require("world_api")
local define = State.define

-- Kit fields on an aura that AuraData does not have; an addon's copy leaves them out.
local KIT_FIELDS = { absorb = true, reduction = true, immune = true, sourceGuid = true }
-- aura -> its expiry timer.
local timers = setmetatable({}, { __mode = "k" })

-- Same filter rule as Units' UnitAura: HARMFUL anywhere in the filter selects harmful auras, anything else helpful.
local function wantsHarmful(filter)
  return type(filter) == "string" and filter:upper():find("HARMFUL", 1, true) ~= nil
end

local function indexOf(actor, aura)
  for i, held in ipairs(actor.auras) do
    if held == aura then
      return i
    end
  end
end

-- A spec decides harmful; without one the spell's record does (harmful = true), else the aura is helpful.
local function isHarmful(w, spec)
  if spec.harmful ~= nil then
    return spec.harmful and true or false
  end
  local record = w.mock.spells[spec.spellID]
  return record ~= nil and record.harmful == true
end

local function sourceToken(w, source)
  if type(source) == "table" then
    return Actors.tokens(w, source)[1]
  end
  return source
end

-- Rewrites actor.absorbs as the sum of its auras' absorb values; scenario code calls it after changing an absorb.
function M.sumAbsorbs(actor)
  local total = 0
  for _, aura in ipairs(actor.auras) do
    total = total + (aura.absorb or 0)
  end
  actor.absorbs = total
end

local function cancel(aura)
  if timers[aura] then
    timers[aura]:Cancel()
    timers[aura] = nil
  end
end

-- source: assumed (row C8) a permanent aura has duration 0 and expirationTime 0; an expiring one expires duration
-- seconds after the world clock now (GetTime).
local function arm(w, actor, aura)
  cancel(aura)
  aura.expirationTime = 0
  if aura.duration > 0 then
    aura.expirationTime = w.now + aura.duration
    timers[aura] = Combat.later(w, aura.duration, function()
      M.remove(w, actor, aura)
    end)
  end
end

-- spec: { spellID, source? (a token or an actor), duration?, stacks?, harmful?, absorb?, reduction?, immune?,
-- dispelName? }. Returns the aura, which is the table actor.auras holds.
function M.apply(w, actor, spec)
  actor.auraSeq = (actor.auraSeq or 0) + 1
  local harmful = isHarmful(w, spec)
  local info = Spells.info(w, spec.spellID)
  -- source: assumed (row C8) an aura that does not stack has applications 0.
  local aura = {
    name = info.name,
    spellId = spec.spellID,
    icon = info.iconID,
    auraInstanceID = actor.auraSeq,
    applications = spec.stacks or 0,
    duration = spec.duration or 0,
    isHelpful = not harmful,
    isHarmful = harmful,
    sourceUnit = sourceToken(w, spec.source),
    sourceGuid = type(spec.source) == "table" and spec.source.guid or nil,
    dispelName = spec.dispelName,
    absorb = spec.absorb,
    reduction = spec.reduction,
    immune = spec.immune,
  }
  actor.auras[#actor.auras + 1] = aura
  arm(w, actor, aura)
  M.sumAbsorbs(actor)
  Combat.emit(w, "aura", actor, { addedAuras = { aura } })
  return aura
end

function M.remove(w, actor, aura)
  local at = indexOf(actor, aura)
  if not at then
    return
  end
  table.remove(actor.auras, at)
  cancel(aura)
  M.sumAbsorbs(actor)
  Combat.emit(w, "aura", actor, { removedAuraInstanceIDs = { aura.auraInstanceID } })
end

local function updated(w, actor, aura)
  M.sumAbsorbs(actor)
  Combat.emit(w, "aura", actor, { updatedAuraInstanceIDs = { aura.auraInstanceID } })
end

-- Restarts the aura's clock from now with its duration (or duration, when given); the instance id stays.
function M.refresh(w, actor, aura, duration)
  if not indexOf(actor, aura) then
    return
  end
  aura.duration = duration or aura.duration
  arm(w, actor, aura)
  updated(w, actor, aura)
end

function M.setStacks(w, actor, aura, stacks)
  if not indexOf(actor, aura) then
    return
  end
  aura.applications = stacks
  updated(w, actor, aura)
end

-- The AuraData an addon sees: a copy without the kit's own fields.
local function publicCopy(aura)
  local out = {}
  for key, value in pairs(aura) do
    if not KIT_FIELDS[key] then
      out[key] = value
    end
  end
  return out
end

M.publicCopy = publicCopy

local function byInstance(data, id)
  for _, aura in ipairs(data.auras or {}) do
    if aura.auraInstanceID == id then
      return aura
    end
  end
end

local function bySpellName(data, name, filter)
  local harmful, index = wantsHarmful(filter), 1
  local aura = UnitsExtra.nthAura(data, index, harmful)
  while aura and aura.name ~= name do
    index = index + 1
    aura = UnitsExtra.nthAura(data, index, harmful)
  end
  return aura
end

-- source: confirmed (rows C8, G1) the C_UnitAuras functions exist on all five flavors and return AuraData; assumed
-- (row G12) GetBuffDataByIndex and GetDebuffDataByIndex add HELPFUL and HARMFUL themselves and a filter without HARMFUL
-- selects helpful auras.
local function installReaders(w)
  local function reader(name, find)
    local qualified = "C_UnitAuras." .. name
    define(w, qualified, function(unit, ...)
      local data = Units.fixture(w.unitState, unit)
      if not data then
        WorldApi.markUnscripted(w, qualified)
        return nil
      end
      local aura = find(data, ...)
      return aura and publicCopy(aura) or nil
    end)
  end
  reader("GetAuraDataByIndex", function(data, index, filter)
    return UnitsExtra.nthAura(data, index, wantsHarmful(filter))
  end)
  reader("GetAuraDataByAuraInstanceID", byInstance)
  reader("GetAuraDataBySpellName", bySpellName)
  reader("GetBuffDataByIndex", function(data, index)
    return UnitsExtra.nthAura(data, index, false)
  end)
  reader("GetDebuffDataByIndex", function(data, index)
    return UnitsExtra.nthAura(data, index, true)
  end)
end

function M.install(w)
  installReaders(w)
  Combat.listen(w, "despawn", function(actor)
    for _, aura in ipairs(actor.auras) do
      cancel(aura)
    end
  end)
end

return M
