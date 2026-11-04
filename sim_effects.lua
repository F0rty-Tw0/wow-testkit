-- SimEffects: what a landed cast does (spec 7.3). SimSpells hangs apply on w.sim.seams.cast; apply plays the effects of the
-- record in order, one handler per effect type. A projectile lands after its flight, a persistent area ticks from the frame
-- hook, and Charge runs the player to the foe itself and holds the rest of its spell until the player arrives. The world reads snapshot: the last two seconds of
-- events plus the live areas and root/stun auras. An effect type no handler knows is ignored and counted in w.unscripted.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local Log = require("combat_log")
local Resolve = require("combat_resolve")
local SimEffectArea = require("sim_effect_area")
local SimEffectState = require("sim_effect_state")
local SimMelee = require("sim_melee")
local SimMove = require("sim_move")
local SimRange = require("sim_range")
local SimSpellChecks = require("sim_spell_checks")
local SimSpellData = require("sim_spell_data")
local WorldApi = require("world_api")

local MS = 1000

local RULES = {
  -- source: assumed (spec 7.3) yards per second a projectile flies; the hit lands distance / speed after the cast.
  PROJECTILE_SPEED = 24,
  -- source: assumed (spec 7.3) a timed spell with a reach over 8 yards throws a projectile; a shorter one hits at once.
  MELEE_REACH = 8,
  -- source: assumed (spec 7.3) Charge runs at 25 yd/s.
  CHARGE_SPEED = 25,
  -- source: assumed (a run must end) a Charge that has not reached melee range this many seconds after it began gives up
  -- and loses the rest of its spell.
  CHARGE_MAX = 1.5,
  -- source: assumed (a data cycle must not hang a cast) the most spells a chain of triggers plays.
  MAX_TRIGGER_DEPTH = 4,
}

M.MAX_TRIGGER_DEPTH = RULES.MAX_TRIGGER_DEPTH

local run

-- Whether victim is still a living actor of the world (a projectile or a cast bar can outlast its foe).
local function standing(w, victim)
  local present = victim ~= nil and w.combat.actors[victim.guid] == victim

  return present and not victim.isDead
end

local function targets(w, ctx, effect)
  local where = effect.target
  if where == "caster" then
    return { ctx.caster }
  elseif where == "areaSource" then
    return SimEffectArea.around(w, ctx.caster.pos, effect.radius or 0)
  elseif where == "areaDest" then
    return ctx.point and SimEffectArea.around(w, ctx.point, effect.radius or 0) or {}
  end
  local victim = ctx.target

  return standing(w, victim) and { victim } or {}
end

-- source: assumed (spec 7.3, no stat scaling) the base points are the damage, rounded down.
local function amountOf(effect)
  return math.max(0, math.floor(effect.base or 0))
end

local function hit(w, caster, victim, rec, effect)
  local at = SimRange.copy(victim.pos)
  SimEffectState.record(w, "hit", { at = at, spellID = rec.id })
  Resolve.damage(w, caster, victim, { amount = amountOf(effect), spellID = rec.id, school = rec.school })
end

local function isProjectile(rec, effect)
  local timed = (rec.castTime or 0) > 0
  local far = (rec.maxRange or 0) > RULES.MELEE_REACH

  return effect.target == "enemy" and timed and far
end

-- source: assumed (a reload drops it) a projectile in flight is not kept; one whose foe died or left the world hits nothing.
local function launch(w, ctx, victim, effect)
  local caster, rec = ctx.caster, ctx.rec
  local from, to = SimRange.copy(caster.pos), SimRange.copy(victim.pos)
  SimEffectState.record(w, "projectile", { from = from, to = to, spellID = rec.id })
  local flight = SimRange.distance(caster, victim) / RULES.PROJECTILE_SPEED
  Combat.later(w, flight, function()
    if standing(w, victim) then
      hit(w, caster, victim, rec, effect)
    end
  end)
end

local function damage(w, ctx, effect)
  for _, victim in ipairs(targets(w, ctx, effect)) do
    if isProjectile(ctx.rec, effect) then
      launch(w, ctx, victim, effect)
    else
      hit(w, ctx.caster, victim, ctx.rec, effect)
    end
  end
end

-- source: assumed (spec 7.3) an aura on another unit is a debuff, on the caster a buff; periodic and dummy auras are held
-- without a tick, and root and stun are the kit-only fields.
local function applyAura(w, ctx, effect, victim)
  local rec, caster = ctx.rec, ctx.caster
  local style = effect.aura
  local aura = Resolve.aura(w, caster, victim, {
    spellID = rec.id,
    duration = (rec.duration or 0) / MS,
    harmful = victim ~= caster,
    root = style == "root" or nil,
    stun = style == "stun" or nil,
  })
  local key = SimEffectState.auraKey(victim.guid, aura.auraInstanceID)
  w.sim.spellAuras[key] = { spellID = rec.id, casterGuid = caster.guid, targetGuid = victim.guid, style = style }
end

local function aura(w, ctx, effect)
  for _, victim in ipairs(targets(w, ctx, effect)) do
    applyAura(w, ctx, effect, victim)
  end
end

-- source: assumed (spec 7.3) the log's amount is the whole gain and overEnergize the part past the maximum.
local function energize(w, ctx, effect)
  for _, victim in ipairs(targets(w, ctx, effect)) do
    local amount = amountOf(effect)
    local room = victim.powerMax - victim.power
    Log.emit(w, "SPELL_ENERGIZE", ctx.caster, victim, {
      spellID = ctx.rec.id,
      amount = amount,
      overEnergize = math.max(0, amount - room),
      powerType = victim.powerType,
      alternatePowerType = 0,
    })
    Actors.setPower(w, victim, victim.power + amount)
  end
end

local function persistent(w, ctx, effect)
  local center = ctx.point or ctx.caster.pos
  SimEffectArea.add(w, ctx.caster, ctx.rec, effect, center, amountOf(effect))
end

-- Turns the player toward victim; facing 0 looks north, so the forward vector (-sin f, cos f) points at it.
local function face(w, victim)
  local from = w.sim.player.pos
  SimMove.setFacing(w, math.atan2(from.x - victim.pos.x, victim.pos.y - from.y))
end

-- Starts the run and holds the spell: the effects after index play when the player arrives (stepCharge). A cast with no
-- target runs nothing.
local function charge(w, ctx, _effect, index)
  local victim = ctx.target
  if not victim then
    return false
  end
  local from, to = SimRange.copy(ctx.caster.pos), SimRange.copy(victim.pos)
  SimEffectState.record(w, "charge", { from = from, to = to, spellID = ctx.rec.id })
  w.sim.charge = { guid = victim.guid, spellID = ctx.rec.id, next = index + 1, deadline = w.now + RULES.CHARGE_MAX }
  w.sim.driven = RULES.CHARGE_SPEED
  face(w, victim)

  return true
end

-- source: assumed (spec 7.3) a trigger plays the other spell's effects on the same target and point, with no checks.
local function trigger(w, ctx, effect)
  local rec = effect.trigger and SimSpellData.get(w, effect.trigger)
  if rec and ctx.depth < RULES.MAX_TRIGGER_DEPTH then
    run(w, { caster = ctx.caster, rec = rec, target = ctx.target, point = ctx.point, depth = ctx.depth + 1 }, 1)
  end
end

local HANDLERS = {
  damage = damage,
  aura = aura,
  energize = energize,
  persistent = persistent,
  charge = charge,
  trigger = trigger,
}

-- Plays the effects of ctx.rec from index first; a handler that answers true holds the rest.
function run(w, ctx, first)
  local effects = ctx.rec.effects or {}
  for i = first, #effects do
    local effect = effects[i]
    local handler = HANDLERS[effect.type]
    if not handler then
      WorldApi.markUnscripted(w, "sim:effect:" .. tostring(effect.type))
    else
      local held = handler(w, ctx, effect, i)
      if held then
        return
      end
    end
  end
end

-- Plays rec's effects for caster at target (an actor) or point ({ x, y }). The seams.cast function.
function M.apply(w, caster, rec, target, point)
  run(w, { caster = caster, rec = rec, target = target, point = point, depth = 1 }, 1)
end

local function stopCharge(w)
  w.sim.charge, w.sim.driven = nil, nil
end

-- Moves the player CHARGE_SPEED * dt yards toward victim, never past it. SimMove.frame leaves the walk to this while
-- sim.driven is set, so a key press or release does not change the run.
local function approach(w, victim, dt)
  local from = w.sim.player.pos
  local dx, dy = victim.pos.x - from.x, victim.pos.y - from.y
  local length = math.sqrt(dx * dx + dy * dy)
  if length == 0 then
    return
  end
  local step = math.min(RULES.CHARGE_SPEED * dt, length)
  SimMove.place(w, from.x + dx / length * step, from.y + dy / length * step)
end

-- source: assumed (spec 7.3) the run ends in melee range and then plays the rest of the spell; the death of the target,
-- the death or a stun of the player, or the deadline ends it without the rest.
local function stepCharge(w, dt)
  local held = w.sim.charge
  if not held then
    return
  end
  local player, victim = w.sim.player, w.combat.actors[held.guid]
  local down = player.isDead or SimSpellChecks.isStunned(player)
  local lost = down or not victim or victim.isDead
  local late = w.now >= held.deadline
  if lost or late then
    stopCharge(w)

    return
  end
  face(w, victim)
  local arrived = SimMelee.inRange(player, victim)
  if not arrived then
    approach(w, victim, dt)
    arrived = SimMelee.inRange(player, victim)
  end
  if not arrived then
    return
  end
  stopCharge(w)
  local rec = SimSpellData.get(w, held.spellID)
  run(w, { caster = player, rec = rec, target = victim, depth = 1 }, held.next)
end

-- One sim frame: the run, the area ticks, and the ring's old events.
function M.step(w, dt)
  stepCharge(w, dt)
  SimEffectArea.step(w)
  SimEffectState.prune(w)
end

-- A world reset ends the run and clears the areas and the ring.
function M.reset(w)
  stopCharge(w)
  SimEffectState.reset(w)
end

M.snapshot = SimEffectState.snapshot

-- Adds the effect state, hangs the effects on the cast seam, the step on the frame hooks and the reset on the reset hooks.
function M.install(w)
  SimEffectState.install(w)
  table.insert(w.sim.seams.cast, M.apply)
  table.insert(w.sim.hooks.frame, M.step)
  table.insert(w.sim.hooks.reset, M.reset)
end

return M
