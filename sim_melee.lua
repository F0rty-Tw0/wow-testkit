-- SimMelee: the player's auto-attack. start needs a living enemy target; each sim frame the swing timer runs down, and a
-- swing that is due lands when the target is in melee range and in front of the player (else one UI error per failure
-- streak, and the swing waits). The attack stops when the target dies, despawns or stops being the player's target.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local Resolve = require("combat_resolve")
local SimRange = require("sim_range")
local SimState = require("sim_state")
local SimTarget = require("sim_target")
local State = require("game.state")
local define = State.define

local TARGET = "target"
local WARRIOR = "WARRIOR"

-- source: assumed (spec 5.2) melee reach is 5 yards, measured after both reaches.
M.RANGE = 5

-- source: assumed (spec 5.2 gives only the speeds) the swing speed in seconds and the damage range per class; the kit
-- has no weapons. Task 5.6 may move this table.
M.KIT = {
  WARRIOR = { speed = 2.6, min = 8, max = 12 },
  MAGE = { speed = 1.8, min = 2, max = 4 },
}

-- The class's kit row; a class without one swings like a warrior.
function M.weapon(actor)
  return M.KIT[actor.classFile] or M.KIT[WARRIOR]
end

-- Whether b is within melee range of a (after both reaches); the edge counts.
function M.inRange(a, b)
  return SimRange.distance(a, b) <= M.RANGE + 1e-6
end

-- The ERR_ name that keeps the swing from landing, or nil: range first, then facing.
local function failure(player, target)
  if not M.inRange(player, target) then
    return "ERR_BADATTACKPOS"
  end
  if not SimRange.inFront(player, target) then
    return "ERR_BADATTACKFACING"
  end

  return nil
end

-- Ends the attack and clears its timer.
function M.stop(w)
  local m = w.sim.melee
  m.on, m.targetGuid, m.timer, m.err = false, nil, 0, nil
end

-- Starts the attack on the player's target. Returns false (nothing changes) without a living enemy target.
function M.start(w)
  local m = w.sim.melee
  local target = w.combat.actors[w.sim.player.targetGuid]
  if not (target and target.isEnemy and not target.isDead) then
    return false
  end
  if m.on and m.targetGuid == target.guid then
    return true
  end
  M.stop(w)
  m.on, m.targetGuid = true, target.guid

  return true
end

-- Lands one swing: deterministic damage from the kit row.
-- grug: deterministic so lupa/WASM parity and tests are exact.
local function swing(w, player, target)
  local weapon = M.weapon(player)
  local count = player.swings or 0
  local amount = weapon.min + count % (weapon.max - weapon.min + 1)
  local m = w.sim.melee
  m.timer, m.err = m.timer + weapon.speed, nil
  local result = Resolve.damage(w, player, target, { amount = amount })
  if not result.missed then
    player.swings = count + 1
  end
end

-- Reports a failed swing once per streak (m.err remembers the reason) and holds the timer at 0 to retry next frame.
-- source: assumed (spec 5.2) one UI_ERROR_MESSAGE per failure streak, not one per frame.
local function hold(w, reason)
  local m = w.sim.melee
  m.timer = 0
  if m.err ~= reason then
    m.err = reason
    SimTarget.uiError(w, reason)
  end
end

-- One sim frame: the timer runs down and a due swing lands or fails.
function M.step(w, dt)
  local m = w.sim.melee
  if not m.on then
    return
  end
  m.timer = m.timer - dt
  if m.timer > 0 then
    return
  end
  local player = w.sim.player
  local target = w.combat.actors[m.targetGuid]
  local reason = failure(player, target)
  if reason then
    hold(w, reason)

    return
  end
  swing(w, player, target)
end

local function stopFor(w, actor)
  if w.sim.melee.targetGuid == actor.guid then
    M.stop(w)
  end
end

-- source: inferred (spec 5.2) the attack stops when the player's target becomes another unit or none.
local function onTarget(w, actor)
  local m = w.sim.melee
  if actor == w.sim.player and m.on and actor.targetGuid ~= m.targetGuid then
    M.stop(w)
  end
end

local function export(w)
  local m = w.sim.melee

  return { on = m.on, targetGuid = m.targetGuid, timer = m.timer, swings = w.sim.player.swings }
end

-- Puts the attack back when its target is still the player's living enemy target; else it stays off.
local function restore(w, data)
  local m = w.sim.melee
  w.sim.player.swings = data.swings
  local target = w.combat.actors[data.targetGuid]
  if not (data.on and target and not target.isDead and w.sim.player.targetGuid == data.targetGuid) then
    return
  end
  m.on, m.targetGuid, m.timer = true, data.targetGuid, data.timer
end

-- Defines StartAttack, AttackTarget and StopAttack, fills the attack action, and hooks the frame, the reset and the
-- reload. StartAttack(unit) targets unit first when it names another actor.
function M.install(w)
  w.sim.melee = { on = false, targetGuid = nil, timer = 0, err = nil }
  w.sim.actions.attack = function()
    M.start(w)
  end
  define(w, "StartAttack", function(unit)
    local actor = Actors.get(w, unit or TARGET)
    if actor then
      SimTarget.target(w, actor)
      M.start(w)
    end
  end)
  define(w, "AttackTarget", function()
    M.start(w)
  end)
  define(w, "StopAttack", function()
    M.stop(w)
  end)
  table.insert(w.sim.hooks.frame, M.step)
  table.insert(w.sim.hooks.reset, M.stop)
  Combat.listen(w, "death", function(actor)
    stopFor(w, actor)
  end)
  Combat.listen(w, "despawn", function(actor)
    stopFor(w, actor)
  end)
  Combat.listen(w, "target", function(actor)
    onTarget(w, actor)
  end)
  SimState.persist(w, "melee", { export = export, restore = restore })
end

return M
