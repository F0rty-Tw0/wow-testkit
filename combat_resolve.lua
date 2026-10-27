-- Resolve: the only code that changes an actor's health from combat; the AI and the timeline call it. An action runs in a
-- fixed order: its checks and numbers, the state change, the threat, then its combat log lines, then the unit events
-- (row C7: the log comes before the unit events of the same action). Health is written directly and its hook emitted after
-- the log, because a setter would fire UNIT_HEALTH first. Every number is scenario data (R4). Casts, auras and dispels
-- live in combat_resolve_spell.lua and are re-exported here.
local M = {}

local Auras = require("combat_auras")
local Casts = require("combat_cast")
local Combat = require("combat")
local Log = require("combat_log")
local Spell = require("combat_resolve_spell")
local State = require("combat_state")
local Threat = require("combat_threat")

local unpack = unpack

local IMMUNE = "IMMUNE"

for name, fn in pairs(Spell) do
  M[name] = fn
end

local function checkAmount(spec, name)
  if type(spec.amount) ~= "number" or spec.amount < 0 then
    error(string.format("Resolve.%s: spec.amount must be a number of 0 or more, got %s", name, tostring(spec.amount)), 3)
  end
end

-- The subevent prefix: no spell is a melee swing.
local function prefixOf(spec)
  if not spec.spellID then
    return "SWING"
  end
  return spec.periodic and "SPELL_PERIODIC" or spec.ranged and "RANGE" or "SPELL"
end

local function isImmune(actor)
  for _, aura in ipairs(actor.auras) do
    if aura.immune then
      return true
    end
  end
  return false
end

-- Multiplies the amount by each reduction aura in turn, rounding down after each.
local function reduced(actor, amount)
  for _, aura in ipairs(actor.auras) do
    if aura.reduction then
      amount = math.floor(amount * aura.reduction)
    end
  end
  return amount
end

-- Takes the amount from the absorb auras in apply order, logging SPELL_ABSORBED for each. Returns what is left, what was
-- absorbed and the auras that took some (an emptied one still sits in the list until the unit events).
local function soak(w, src, dst, spec, amount)
  local absorbed, touched = 0, {}
  for _, aura in ipairs(dst.auras) do
    if amount > 0 and (aura.absorb or 0) > 0 then
      local taken = math.min(amount, aura.absorb)
      aura.absorb = aura.absorb - taken
      amount, absorbed = amount - taken, absorbed + taken
      Auras.sumAbsorbs(dst)
      touched[#touched + 1] = aura
      Log.emit(w, "SPELL_ABSORBED", src, dst, {
        spellID = spec.spellID,
        caster = w.combat.actors[aura.sourceGuid] or dst,
        absorbSpellID = aura.spellId,
        amount = taken,
      })
    end
  end
  return amount, absorbed, touched
end

-- Marks the actor dead and logs UNIT_DIED; the state change that fires events is finishDeath.
local function declareDead(w, actor)
  actor.isDead = true
  Log.emit(w, "UNIT_DIED", nil, actor)
end

-- Clears the dead actor's auras, cast and threat list, then emits "death": State.disengage and Ai.stop listen to it.
local function finishDeath(w, actor)
  for _, aura in ipairs({ unpack(actor.auras) }) do
    Auras.remove(w, actor, aura)
  end
  Casts.interrupt(w, actor)
  Casts.stopChannel(w, actor)
  Threat.clear(w, actor)
  Combat.emit(w, "death", actor)
end

local function announceHealth(w, actor, old)
  if actor.health ~= old then
    Combat.emit(w, "health", actor, old)
  end
end

-- spec: { amount, spellID?, school?, crit?, periodic?, ranged?, miss? }; no spellID is a SWING_ hit. Order: immunity or a
-- miss spec (logged as _MISSED, nothing else happens), reduction auras, absorb auras, health, threat and engagement, the
-- log, the unit events, death. Returns { dealt, absorbed, overkill, missed? }: dealt is the damage that got past the
-- absorbs, overkill the part of it beyond the health (0 when none, row C4).
function M.damage(w, src, dst, spec)
  checkAmount(spec, "damage")
  local result = { dealt = 0, absorbed = 0, overkill = 0 }
  if dst.isDead then
    return result
  end
  local prefix = prefixOf(spec)
  local missType = isImmune(dst) and IMMUNE or spec.miss
  if missType then
    Log.emit(w, prefix .. "_MISSED", src, dst, { spellID = spec.spellID, missType = missType })
    result.missed = missType
    return result
  end
  local dealt, absorbed, touched = soak(w, src, dst, spec, reduced(dst, spec.amount))
  local old = dst.health
  dst.health = math.max(0, old - dealt)
  local lethal = dealt > 0 and dst.health == 0
  result.dealt, result.absorbed, result.overkill = dealt, absorbed, math.max(0, dealt - old)
  -- Threat lists belong to enemies: only a hit on an enemy by a non-enemy adds to one.
  if dst.isEnemy and not src.isEnemy then
    Threat.add(w, dst, src, dealt * (src.threatMod or 1))
  end
  State.engage(w, src, dst)
  Log.emit(w, prefix .. "_DAMAGE", src, dst, {
    spellID = spec.spellID,
    amount = dealt,
    overkill = result.overkill,
    school = spec.school,
    absorbed = absorbed > 0 and absorbed or nil,
    critical = spec.crit and true or nil,
  })
  if lethal then
    declareDead(w, dst)
  end
  for _, aura in ipairs(touched) do
    if aura.absorb > 0 then
      Combat.emit(w, "aura", dst, { updatedAuraInstanceIDs = { aura.auraInstanceID } })
    else
      Auras.remove(w, dst, aura)
    end
  end
  announceHealth(w, dst, old)
  if lethal then
    finishDeath(w, dst)
  end
  return result
end

-- spec: { amount, spellID, crit?, periodic? }. The health rises to the maximum at most; the log's amount is the whole heal
-- and its overhealing the part that did not fit. Returns { healed, overheal }; a dead target takes nothing.
function M.heal(w, src, dst, spec)
  checkAmount(spec, "heal")
  if dst.isDead then
    return { healed = 0, overheal = 0 }
  end
  local old = dst.health
  dst.health = math.min(dst.healthMax, old + spec.amount)
  local healed = dst.health - old
  local overheal = spec.amount - healed
  Log.emit(w, spec.periodic and "SPELL_PERIODIC_HEAL" or "SPELL_HEAL", src, dst, {
    spellID = spec.spellID,
    amount = spec.amount,
    overhealing = overheal,
    critical = spec.crit and true or nil,
  })
  announceHealth(w, dst, old)
  return { healed = healed, overheal = overheal }
end

-- Health 0, dead, UNIT_DIED (no source), UNIT_HEALTH, then auras, cast and threat list cleared and the "death" hook. Does
-- nothing to a dead actor.
function M.kill(w, actor)
  if actor.isDead then
    return
  end
  local old = actor.health
  actor.health = 0
  declareDead(w, actor)
  announceHealth(w, actor, old)
  finishDeath(w, actor)
end

-- Brings a dead or ghost actor back with health (capped at the maximum): clears isDead and isGhost, logs SPELL_RESURRECT
-- from src with spellID when src is given, then emits the "health" and "flags" hooks (UNIT_HEALTH, UNIT_FLAGS). Returns false
-- when the actor was neither dead nor a ghost.
function M.revive(w, actor, health, src, spellID)
  if type(health) ~= "number" then
    error("Resolve.revive: health must be a number, got " .. type(health), 2)
  end
  if src and not spellID then
    error("Resolve.revive: a resurrection by src needs the id of the spell that does it", 2)
  end
  if not (actor.isDead or actor.isGhost) then
    return false
  end
  local old = actor.health
  actor.health = math.max(0, math.min(health, actor.healthMax))
  actor.isDead, actor.isGhost = false, false
  if src then
    Log.emit(w, "SPELL_RESURRECT", src, actor, { spellID = spellID })
  end
  announceHealth(w, actor, old)
  Combat.emit(w, "flags", actor)
  return true
end

return M
