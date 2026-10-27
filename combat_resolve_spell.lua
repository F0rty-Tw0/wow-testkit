-- Spell-driven combat actions: casts, interrupts, failures, auras, stack changes and dispels. Each writes its combat log
-- line before the state change that fires unit events (row C7), then calls the Casts and Auras modules. Re-exported by
-- combat_resolve.lua as Resolve.*.
local M = {}

local Auras = require("combat_auras")
local Casts = require("combat_cast")
local Combat = require("combat")
local Log = require("combat_log")
local Spells = require("combat_spells")

local MS = 1000

local function needSpell(spellID, name)
  if not spellID then
    error("Resolve." .. name .. ": needs the id of the spell that does it", 3)
  end
end

local function auraType(aura)
  return aura.isHarmful and "DEBUFF" or "BUFF"
end

local function holds(actor, aura)
  for _, held in ipairs(actor.auras) do
    if held == aura then
      return true
    end
  end
  return false
end

-- spec: { spellID, castTime? (seconds; else the spell's castTime in milliseconds), target? (an actor), notInterruptible?,
-- effect? = function }. A cast with a time logs SPELL_CAST_START, begins the cast and, when it ends, logs
-- SPELL_CAST_SUCCESS, finishes the cast and runs the effect; a cast that was interrupted, failed or cleared meanwhile never
-- runs it. Without a time the cast is instant: SPELL_CAST_SUCCESS and the effect at once, and no UNIT_SPELLCAST_* events
-- (the Casts module has no instant path). Returns the cast record, nil for an instant cast.
function M.cast(w, src, spec)
  if src.cast or src.channel then
    error("Resolve.cast: " .. tostring(src.name) .. " is already casting", 2)
  end
  local info = Spells.info(w, spec.spellID)
  local seconds = spec.castTime or (info.castTime and info.castTime / MS) or 0
  local params = { spellID = spec.spellID }
  if seconds <= 0 then
    Log.emit(w, "SPELL_CAST_SUCCESS", src, spec.target, params)
    if spec.effect then
      spec.effect()
    end
    return nil
  end
  Log.emit(w, "SPELL_CAST_START", src, spec.target, params)
  local record = Casts.begin(w, src, { spellID = spec.spellID, duration = seconds, notInterruptible = spec.notInterruptible })
  Combat.later(w, seconds, function()
    if src.cast ~= record then
      return
    end
    Log.emit(w, "SPELL_CAST_SUCCESS", src, spec.target, params)
    Casts.finish(w, src)
    if spec.effect then
      spec.effect()
    end
  end)
  return record
end

-- src interrupts dst's cast or channel with spellID: SPELL_INTERRUPT, then the cast ends as interrupted. Returns false and
-- logs nothing when dst is not casting or its cast cannot be interrupted.
function M.interrupt(w, src, dst, spellID)
  needSpell(spellID, "interrupt")
  local record = dst.cast or dst.channel
  if not record or record.notInterruptible then
    return false
  end
  Log.emit(w, "SPELL_INTERRUPT", src, dst, { spellID = spellID, extraSpellID = record.spellID })
  if dst.cast then
    Casts.interrupt(w, dst, src)
  else
    Casts.stopChannel(w, dst, src)
  end
  return true
end

-- Fails src's cast: SPELL_CAST_FAILED with failedType (scenario data, e.g. "Not enough mana"), then the cast ends as failed.
-- Returns false when src is not casting.
function M.fail(w, src, failedType)
  local record = src.cast
  if not record then
    return false
  end
  Log.emit(w, "SPELL_CAST_FAILED", src, nil, { spellID = record.spellID, failedType = failedType })
  Casts.fail(w, src)
  return true
end

-- Applies an aura on dst from src (an actor or nil): SPELL_AURA_APPLIED, then Auras.apply with the same spec. Returns the aura.
function M.aura(w, src, dst, spec)
  local harmful = Auras.isHarmful(w, spec)
  Log.emit(w, "SPELL_AURA_APPLIED", src, dst, {
    spellID = spec.spellID,
    auraType = harmful and "DEBUFF" or "BUFF",
    remainingPoints = spec.absorb,
  })
  local applied = { source = src }
  for key, value in pairs(spec) do
    applied[key] = value
  end
  return Auras.apply(w, dst, applied)
end

-- Sets an aura's stacks; a rise logs SPELL_AURA_APPLIED_DOSE with the new count, a fall logs nothing.
function M.stacks(w, actor, aura, stacks)
  if stacks > aura.applications and holds(actor, aura) then
    local src = w.combat.actors[aura.sourceGuid]
    Log.emit(w, "SPELL_AURA_APPLIED_DOSE", src, actor, { spellID = aura.spellId, auraType = auraType(aura), amount = stacks })
  end
  Auras.setStacks(w, actor, aura, stacks)
end

-- src dispels aura from dst with spellID: SPELL_DISPEL, then Auras.remove.
function M.dispel(w, src, dst, aura, spellID)
  needSpell(spellID, "dispel")
  Log.emit(w, "SPELL_DISPEL", src, dst, { spellID = spellID, extraSpellID = aura.spellId, auraType = auraType(aura) })
  Auras.remove(w, dst, aura)
end

return M
