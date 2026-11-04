-- SimSpells: the player's cast pipeline (spec 7.2). cast runs the checks in order (the first failure wins and shows as a
-- UI error plus UNIT_SPELLCAST_FAILED), then plays the spell: an instant spell succeeds at once, a timed one fills the cast
-- bar (combat_cast) and succeeds when it ends. Moving or a stun interrupts a timed cast. The GCD starts with the cast and
-- a spell's own cooldown on success (sim_spell_cooldowns.lua), and the cost is paid when the cast succeeds (SimPower.spend).
-- Effects are not here: units that play them hang a function on w.sim.seams.cast, a cast request that passes its checks calls
-- w.sim.seams.accept (SimGround ends its targeting mode), and a ground spell cast with no point calls w.sim.seams.ground
-- (SimGround's targeting mode, which also defines SpellStopCasting on top of M.stop).
local M = {}

local Actors = require("combat_actors")
local Casts = require("combat_cast")
local Combat = require("combat")
local Log = require("combat_log")
local Checks = require("sim_spell_checks")
local Cooldowns = require("sim_spell_cooldowns")
local SimPower = require("sim_power")
local SimSpellData = require("sim_spell_data")
local SimState = require("sim_state")
local SimTarget = require("sim_target")
local State = require("game.state")
local define = State.define

local MS = 1000

-- source: assumed (spec 7.2) the nominal global cooldown in seconds; a record's gcd (milliseconds) is what plays.
M.GCD = 1.5

local SLACK = Checks.SLACK

-- The rules a cast passes (sim_spell_checks.lua) and the walk test they use.
M.check = Checks.check
M.isMoving = Checks.isMoving
M.cooldown = Cooldowns.get

local function castInfo(w, spellID)
  return { castGUID = Actors.newCastGuid(w, spellID), spellID = spellID }
end

local function fail(w, caster, spellID, name)
  SimTarget.uiError(w, name)
  Combat.emit(w, "cast", caster, "FAILED", castInfo(w, spellID))

  return false, name
end

-- source: assumed (spec 7.2) the cost is taken when the cast succeeds: at once for an instant spell, when the bar ends for a
-- timed one. Answers whether the caster could pay (the checks proved it at the request; a timed bar can lose it on the way).
local function pay(w, caster, rec)
  local cost = rec.cost
  if not cost then
    return true
  end

  return SimPower.spend(w, caster, cost.type, cost.amount)
end

local function land(w, caster, rec, target, point)
  for _, fn in ipairs(w.sim.seams.cast) do
    fn(w, caster, rec, target, point)
  end
end

-- source: assumed (spec 7.2; the client's event order for an instant spell is not traced) an instant cast sends
-- UNIT_SPELLCAST_SUCCEEDED with no START and succeeds at once; the Casts module has no instant path, so this unit emits it.
local function playInstant(w, caster, rec, target, point)
  pay(w, caster, rec) -- the checks just proved the funds
  Log.emit(w, "SPELL_CAST_SUCCESS", caster, target, { spellID = rec.id })
  Combat.emit(w, "cast", caster, "SUCCEEDED", castInfo(w, rec.id))
  Cooldowns.stamp(w, rec, true, true)
  land(w, caster, rec, target, point)
end

-- The bar ends when the timer fires: the cost, SPELL_CAST_SUCCESS, SUCCEEDED, then the spell's own cooldown and the effects;
-- a caster who can no longer pay gets the power error and an interrupted bar instead. The timer runs SLACK early because
-- the sim clock adds 1/60 s frames and 150 of them fall about 2e-12 short of 2.5 s, so s:simStep(castTime) would miss the
-- end; the bar itself keeps the exact castTime.
-- source: assumed (spec 7.2) the GCD starts with the bar and the spell's own cooldown when the bar ends.
local function playTimed(w, caster, rec, target, point)
  local seconds = rec.castTime / MS
  local params = { spellID = rec.id }
  local gcdBefore = w.sim.gcdEnd
  Log.emit(w, "SPELL_CAST_START", caster, target, params)
  local bar = Casts.begin(w, caster, { spellID = rec.id, duration = seconds })
  local pending = { gcdBefore = gcdBefore }
  w.sim.pending = pending
  pending.gcdStarted = Cooldowns.stamp(w, rec, true, false)
  Combat.later(w, seconds - SLACK, function()
    if caster.cast ~= bar then
      return
    end
    if not pay(w, caster, rec) then
      Casts.interrupt(w, caster)

      return
    end
    Log.emit(w, "SPELL_CAST_SUCCESS", caster, target, params)
    Casts.finish(w, caster)
    Cooldowns.stamp(w, rec, false, true)
    land(w, caster, rec, target, point)
  end)
end

local function play(w, caster, rec, target, point)
  if (rec.castTime or 0) > 0 then
    playTimed(w, caster, rec, target, point)
  else
    playInstant(w, caster, rec, target, point)
  end
end

-- Casts spellID for caster at target (default: the caster's target) or point. Returns true, or false and the failure name.
function M.cast(w, caster, spellID, target, point)
  local rec = SimSpellData.get(w, spellID)
  local goal = target or w.combat.actors[caster.targetGuid]
  local name = Checks.check(w, caster, rec, goal, point)
  if Checks.awaitsPoint(rec, name, point) and w.sim.seams.ground then
    w.sim.seams.ground(w, rec)

    return true
  end
  if name then
    return fail(w, caster, spellID, name)
  end
  for _, fn in ipairs(w.sim.seams.accept) do
    fn(w, rec)
  end
  play(w, caster, rec, goal, point)

  return true
end

-- SpellStopCasting: ends the caster's cast bar as interrupted. Returns whether there was one.
function M.stop(w, caster)
  if not caster.cast then
    return false
  end
  Casts.interrupt(w, caster)

  return true
end

-- Keeps player.casting (what SimWorld reads) in step with the cast bar; a bar that ends without success gives its GCD back.
-- source: assumed (spec 7.2) an interrupted cast leaves no global cooldown.
local function onCast(w, actor, phase, cast)
  local pending = w.sim.pending
  if actor ~= w.sim.player then
    return
  end
  if phase == "START" then
    actor.casting = { spellID = cast.spellID, start = cast.startTimeMs / MS, endTime = cast.endTimeMs / MS }
  elseif phase == "SUCCEEDED" and pending then
    pending.succeeded = true
  elseif phase == "STOP" then
    actor.casting, w.sim.pending = nil, nil
    if pending and not pending.succeeded then
      w.sim.gcdEnd = pending.gcdBefore
      if pending.gcdStarted then
        Cooldowns.release(w)
      end
    end
  end
end

-- One sim frame: a stun or a walk intent interrupts the timed cast this unit started.
function M.step(w)
  local player = w.sim.player
  local stopped = Checks.isStunned(player) or Checks.isMoving(w)
  if w.sim.pending and player.cast and stopped then
    Casts.interrupt(w, player)
  end
end

-- A world reset also ends the cast and clears every cooldown. source: assumed (a reset is a fresh login).
function M.reset(w)
  M.stop(w, w.sim.player)
  Cooldowns.reset(w)
end

-- The cooldowns and the GCD (sim_spell_cooldowns.lua); a cast in flight is not kept, and neither is its GCD.
-- source: assumed (a reload drops it).
local function export(w)
  local data = Cooldowns.export(w)
  local pending = w.sim.pending
  local casting = pending and not pending.succeeded
  data.gcdEnd = casting and pending.gcdBefore or data.gcdEnd

  return data
end

local function castWith(w, id, unit)
  local target = type(unit) == "string" and Actors.get(w, unit) or nil
  M.cast(w, w.sim.player, id, target)
end

local function defineFakes(w)
  define(w, "CastSpellByID", function(id, unit)
    castWith(w, id, unit)
  end)
  define(w, "CastSpellByName", function(name, unit)
    local id = State.findRecord(w.mock.spells, name)
    if id then
      castWith(w, id, unit)
    end
  end)
  define(w, "UseAction", function(slot, unit)
    local entry = w.mock.actions[slot]
    if type(entry) == "table" and entry.type == "spell" then
      castWith(w, entry.id, unit)
    end
  end)
end

-- Adds the cooldown state and the seams, defines the cast fakes, and hooks the frame, the reset and the reload.
function M.install(w)
  local sim = w.sim
  Cooldowns.install(w)
  sim.seams = { swing = {}, pointer = {}, cast = {}, accept = {} }
  defineFakes(w)
  table.insert(sim.hooks.frame, M.step)
  table.insert(sim.hooks.reset, M.reset)
  Combat.listen(w, "cast", function(actor, phase, cast)
    onCast(w, actor, phase, cast)
  end)
  SimState.persist(w, "spells", { export = export, restore = Cooldowns.restore })
end

return M
