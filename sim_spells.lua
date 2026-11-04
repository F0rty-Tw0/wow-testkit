-- SimSpells: the player's cast pipeline (spec 7.2). cast runs the checks in order (the first failure wins and shows as a
-- UI error plus UNIT_SPELLCAST_FAILED), then plays the spell: an instant spell succeeds at once, a timed one fills the cast
-- bar (combat_cast) and succeeds when it ends. Moving or a stun interrupts a timed cast. The GCD starts with the cast and
-- a spell's own cooldown on success; both live in w.sim as plain data and in w.mock.spells[id].cooldown for the readers.
-- Effects are not here: units that play them hang a function on w.sim.seams.cast.
local M = {}

local Actors = require("combat_actors")
local Casts = require("combat_cast")
local Combat = require("combat")
local Log = require("combat_log")
local Checks = require("sim_spell_checks")
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

local function castInfo(w, spellID)
  return { castGUID = Actors.newCastGuid(w, spellID), spellID = spellID }
end

local function fail(w, caster, spellID, name)
  SimTarget.uiError(w, name)
  Combat.emit(w, "cast", caster, "FAILED", castInfo(w, spellID))

  return false, name
end

-- The world-clock second the spell's cooldown started and how many seconds it lasts; 0, 0 when it has none.
function M.cooldown(w, spellID)
  local cooldown = w.sim.cooldowns[spellID]
  if not cooldown then
    return 0, 0
  end

  return cooldown.start, cooldown.duration
end

local function mirror(w, id, start, duration)
  SimSpellData.publish(w, id)
  local entry = w.mock.spells[id] or {}
  w.mock.spells[id] = entry
  entry.cooldown = { start = start, duration = duration, enabled = true }
end

local function startOwn(w, rec)
  local seconds = (rec.cooldown or 0) / MS
  if seconds <= 0 then
    return false
  end
  w.sim.cooldowns[rec.id] = { start = w.now, duration = seconds }
  mirror(w, rec.id, w.now, seconds)

  return true
end

local function startGcd(w, rec)
  local seconds = (rec.gcd or 0) / MS
  if seconds <= 0 then
    return false
  end
  w.sim.gcdEnd, w.sim.gcdSpell = w.now + seconds, rec.id
  mirror(w, rec.id, w.now, seconds)

  return true
end

-- Takes the GCD off the spell that shows it: its mirror goes back to the spell's own cooldown, or to none.
local function releaseGcd(w)
  local id = w.sim.gcdSpell
  local entry = id and w.mock.spells[id]
  w.sim.gcdSpell = nil
  if not entry then
    return
  end
  local own = w.sim.cooldowns[id]
  if own then
    mirror(w, id, own.start, own.duration)
  else
    entry.cooldown = nil
  end
  Combat.fire(w, "ACTIONBAR_UPDATE_COOLDOWN")
  Combat.fire(w, "SPELL_UPDATE_COOLDOWN")
end

-- Starts the GCD and/or the spell's own cooldown (the own one wins the mirror) and announces them once. Answers whether
-- the GCD started.
local function stamp(w, rec, withGcd, withOwn)
  local gcd = withGcd and startGcd(w, rec)
  local own = withOwn and startOwn(w, rec)
  if gcd or own then
    Combat.fire(w, "ACTIONBAR_UPDATE_COOLDOWN")
    Combat.fire(w, "SPELL_UPDATE_COOLDOWN")
  end

  return gcd
end

local function land(w, caster, rec, target, point)
  for _, fn in ipairs(w.sim.seams.cast) do
    fn(w, caster, rec, target, point)
  end
end

-- source: assumed (spec 7.2; the client's event order for an instant spell is not traced) an instant cast sends
-- UNIT_SPELLCAST_SUCCEEDED with no START and succeeds at once; the Casts module has no instant path, so this unit emits it.
local function playInstant(w, caster, rec, target, point)
  Log.emit(w, "SPELL_CAST_SUCCESS", caster, target, { spellID = rec.id })
  Combat.emit(w, "cast", caster, "SUCCEEDED", castInfo(w, rec.id))
  stamp(w, rec, true, true)
  land(w, caster, rec, target, point)
end

-- The bar ends when the timer fires: SPELL_CAST_SUCCESS, SUCCEEDED, then the spell's own cooldown and the effects. The
-- timer runs SLACK early because the sim clock adds 1/60 s frames and 150 of them fall about 2e-12 short of 2.5 s, so
-- s:simStep(castTime) would miss the end; the bar itself keeps the exact castTime.
-- source: assumed (spec 7.2) the GCD starts with the bar and the spell's own cooldown when the bar ends.
local function playTimed(w, caster, rec, target, point)
  local seconds = rec.castTime / MS
  local params = { spellID = rec.id }
  local gcdBefore = w.sim.gcdEnd
  Log.emit(w, "SPELL_CAST_START", caster, target, params)
  local bar = Casts.begin(w, caster, { spellID = rec.id, duration = seconds })
  local pending = { gcdBefore = gcdBefore }
  w.sim.pending = pending
  pending.gcdStarted = stamp(w, rec, true, false)
  Combat.later(w, seconds - SLACK, function()
    if caster.cast ~= bar then
      return
    end
    Log.emit(w, "SPELL_CAST_SUCCESS", caster, target, params)
    Casts.finish(w, caster)
    stamp(w, rec, false, true)
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
  if name then
    return fail(w, caster, spellID, name)
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
        releaseGcd(w)
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
  for id in pairs(w.sim.cooldowns) do
    w.mock.spells[id].cooldown = nil
  end
  w.sim.cooldowns, w.sim.gcdEnd = {}, 0
  releaseGcd(w)
end

local function byId(a, b)
  return a.id < b.id
end

-- The running cooldowns as a list and the GCD end; a cast in flight is not kept, and neither is its GCD.
-- source: assumed (a reload drops it).
local function export(w)
  local running = {}
  for id, cooldown in pairs(w.sim.cooldowns) do
    if cooldown.start + cooldown.duration > w.now then
      running[#running + 1] = { id = id, start = cooldown.start, duration = cooldown.duration }
    end
  end
  table.sort(running, byId)
  local pending = w.sim.pending
  local casting = pending and not pending.succeeded
  local gcdEnd = casting and pending.gcdBefore or w.sim.gcdEnd

  return { cooldowns = running, gcdEnd = gcdEnd }
end

local function restore(w, data)
  w.sim.gcdEnd = data.gcdEnd
  for _, item in ipairs(data.cooldowns) do
    w.sim.cooldowns[item.id] = { start = item.start, duration = item.duration }
    mirror(w, item.id, item.start, item.duration)
  end
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
  define(w, "SpellStopCasting", function()
    return M.stop(w, w.sim.player)
  end)
end

-- Adds the cooldown state and the seams, defines the cast fakes, and hooks the frame, the reset and the reload.
function M.install(w)
  local sim = w.sim
  sim.cooldowns, sim.gcdEnd = {}, 0
  sim.seams = { swing = {}, pointer = {}, cast = {} }
  defineFakes(w)
  table.insert(sim.hooks.frame, M.step)
  table.insert(sim.hooks.reset, M.reset)
  Combat.listen(w, "cast", function(actor, phase, cast)
    onCast(w, actor, phase, cast)
  end)
  SimState.persist(w, "spells", { export = export, restore = restore })
end

return M
