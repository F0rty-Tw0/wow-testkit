-- SimSpellChecks: the rules a cast must pass (spec 7.2), one function per rule, in order; the first one a spell breaks
-- answers its ERR_/SPELL_FAILED_ name. Pure reads of the world; SimSpells plays what passes.
local M = {}

local Auras = require("combat_auras")
local SimRange = require("sim_range")

local RULES = {
  -- source: assumed (float slack) a cooldown that ends this frame counts as over.
  SLACK = 1e-6,
  -- source: assumed (spec 7.2) the walk intents that count as moving; turning does not.
  MOVES = { "forward", "backward", "strafeLeft", "strafeRight", "autorun" },
  -- source: assumed (spec 7.2) a spell whose effects all hit the caster or the area around it needs no target.
  SELF_TARGETS = { caster = true, areaSource = true },
  -- source: assumed (spec 7.2 order); confirmed (names: retail extract strings, builds 70575 and 70688)
  FAIL = {
    NOT_READY = "SPELL_FAILED_NOT_READY",
    IN_PROGRESS = "SPELL_FAILED_SPELL_IN_PROGRESS",
    STUNNED = "SPELL_FAILED_STUNNED",
    MANA = "ERR_OUT_OF_MANA",
    RAGE = "ERR_OUT_OF_RAGE",
    NO_TARGET = "SPELL_FAILED_BAD_IMPLICIT_TARGETS",
    OUT_OF_RANGE = "SPELL_FAILED_OUT_OF_RANGE",
    TOO_CLOSE = "SPELL_FAILED_TOO_CLOSE",
    NOT_INFRONT = "SPELL_FAILED_UNIT_NOT_INFRONT",
    MOVING = "SPELL_FAILED_MOVING",
  },
}
local FAIL = RULES.FAIL

M.SLACK = RULES.SLACK
M.FAIL = FAIL

-- Whether a walk intent is held (SimMove's intents; the player may not have moved a frame yet).
function M.isMoving(w)
  local intents = w.sim.intents
  for _, name in ipairs(RULES.MOVES) do
    if intents[name] then
      return true
    end
  end

  return false
end

function M.isStunned(actor)
  return Auras.has(actor, "stun")
end

-- Whether the spell needs neither a target nor a point: it has effects and every one hits the caster or its surroundings.
local function isSelfCast(rec)
  local effects = rec.effects or {}
  for _, effect in ipairs(effects) do
    if not RULES.SELF_TARGETS[effect.target] then
      return false
    end
  end

  return #effects > 0
end

-- The place a ranged check measures to: the point of a ground spell, the target of a targeted one, nil for a self cast.
local function aim(rec, target, point)
  if rec.ground then
    return point and { pos = point, reach = 0 } or nil
  end
  local selfCast = isSelfCast(rec)
  if selfCast then
    return nil
  end

  return target
end

-- The rules below answer an ERR_/SPELL_FAILED_ name or nil, in the order of spec 7.2.
local function known(w, _caster, rec)
  local entry = rec and w.mock.spells[rec.id]
  if entry and entry.known == true then
    return nil
  end

  return FAIL.NOT_READY
end

local function ready(w, _caster, rec)
  local cooldown = w.sim.cooldowns[rec.id]
  local onCooldown = cooldown and w.now + RULES.SLACK < cooldown.start + cooldown.duration
  local onGcd = (rec.gcd or 0) > 0 and w.now + RULES.SLACK < w.sim.gcdEnd
  if onCooldown or onGcd then
    return FAIL.NOT_READY
  end

  return nil
end

local function idle(_w, caster)
  if caster.cast or caster.channel then
    return FAIL.IN_PROGRESS
  end

  return nil
end

local function notStunned(_w, caster)
  local stunned = M.isStunned(caster)
  if stunned then
    return FAIL.STUNNED
  end

  return nil
end

-- A cost in a power the caster does not use counts as having none of it.
local function enoughPower(_w, caster, rec)
  local cost = rec.cost
  if not cost then
    return nil
  end
  local have = caster.powerToken == cost.type and caster.power or 0
  if have >= cost.amount then
    return nil
  end

  return FAIL[cost.type]
end

local function hasTarget(_w, _caster, rec, target, point)
  if rec.ground then
    return point == nil and FAIL.NO_TARGET or nil
  end
  local livingEnemy = target and target.isEnemy and not target.isDead
  local selfCast = isSelfCast(rec)
  if selfCast or livingEnemy then
    return nil
  end

  return FAIL.NO_TARGET
end

-- A max range of 0 or none is unlimited.
local function inRange(_w, caster, rec, target, point)
  local goal = aim(rec, target, point)
  if not goal then
    return nil
  end
  local gap = SimRange.distance(caster, goal)
  local maxRange = rec.maxRange or 0
  if maxRange > 0 and gap > maxRange then
    return FAIL.OUT_OF_RANGE
  end
  if gap < (rec.minRange or 0) then
    return FAIL.TOO_CLOSE
  end

  return nil
end

local function facing(_w, caster, rec, target)
  local aimless = rec.ground or isSelfCast(rec)
  if aimless then
    return nil
  end
  local ahead = SimRange.inFront(caster, target)
  if ahead then
    return nil
  end

  return FAIL.NOT_INFRONT
end

local function standing(w, caster, rec)
  local timed = (rec.castTime or 0) > 0
  local walking = M.isMoving(w)
  if timed and caster == w.sim.player and walking then
    return FAIL.MOVING
  end

  return nil
end

local CHECKS = { known, ready, idle, notStunned, enoughPower, hasTarget, inRange, facing, standing }

-- Whether a failed check is only the missing point of a ground spell: every rule before the point rule passed, so the
-- spell can open the targeting mode (spec 7.6).
function M.awaitsPoint(rec, name, point)
  local missing = name == FAIL.NO_TARGET and point == nil

  return missing and rec ~= nil and rec.ground == true
end

-- The name of the first rule rec breaks for caster casting at target (an actor) or point ({x, y}), or nil. rec may be nil
-- (an unknown spell).
function M.check(w, caster, rec, target, point)
  for _, rule in ipairs(CHECKS) do
    local name = rule(w, caster, rec, target, point)
    if name then
      return name
    end
  end

  return nil
end

return M
