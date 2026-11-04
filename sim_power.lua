-- SimPower: the player's rage and mana (spec 7.5). Rage rises with a landed swing (the swing seam) and with damage taken
-- (the health hook) and decays out of combat; mana regenerates. Both move in whole seconds from the frame hook, and every
-- change goes through Actors.setPower, so UNIT_POWER_UPDATE fires and the maximum clamps. Units are the points a player
-- sees (a rage cost in a record is already divided by ten, the Task 5.1 finding), never DB2's tenths. spend takes a cast's cost.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local SimSpellChecks = require("sim_spell_checks")
local SimTarget = require("sim_target")

local TICK = 1
local RAGE_TOKEN = "RAGE"
local MANA_TOKEN = "MANA"

-- source: assumed (spec 7.5 gives no numbers; the proof PNG is not number-sensitive) rage per landed player swing, the
-- factor on damage taken as a share of the maximum health, rage lost per second out of combat, and the rage maximum.
M.RAGE = { perHit = 5, takenFactor = 25, decay = 1, max = 100 }

-- source: assumed (spec 7.5) a mana regeneration of this share of the maximum per second, always (no five-second rule).
M.MANA = { regen = 0.01 }

local function gain(w, actor, amount)
  Actors.setPower(w, actor, actor.power + amount)
end

-- source: assumed (spec 7.5) a swing that lands pays rage; a dodged one never reaches the landed call.
local function onSwing(w, attacker, _target, spec)
  if spec.landed and attacker.powerToken == RAGE_TOKEN then
    gain(w, attacker, M.RAGE.perHit)
  end
end

-- source: assumed (spec 7.5) the player's health falling is damage taken, whole rage points rounded down; the blow that
-- kills pays nothing.
local function onHealth(w, actor, old)
  local lost = old - actor.health
  local player = w.sim.player
  local pays = actor == player and player.powerToken == RAGE_TOKEN and lost > 0 and not actor.isDead and actor.healthMax > 0
  if pays then
    gain(w, player, math.floor(M.RAGE.takenFactor * lost / actor.healthMax))
  end
end

-- One whole second: mana regenerates; rage decays unless the player is in combat.
local function perSecond(w)
  local player = w.sim.player
  if player.powerToken == MANA_TOKEN then
    gain(w, player, M.MANA.regen * player.powerMax)
  elseif player.powerToken == RAGE_TOKEN and not player.affectingCombat then
    gain(w, player, -M.RAGE.decay)
  end
end

-- One sim frame. The slack lets 60 frames of 1/60 s count as the second they are.
function M.step(w, dt)
  local clock = w.sim.power
  clock.elapsed = clock.elapsed + dt
  if clock.elapsed + SimSpellChecks.SLACK < TICK then
    return
  end
  clock.elapsed = clock.elapsed - TICK
  perSecond(w)
end

-- Takes amount of the power kind from actor. A short actor (or one of another power) keeps all it has, the UI error
-- names the power, and the answer is false.
function M.spend(w, actor, kind, amount)
  local have = actor.powerToken == kind and actor.power or 0
  if have < amount then
    SimTarget.uiError(w, SimSpellChecks.FAIL[kind])

    return false
  end
  Actors.setPower(w, actor, actor.power - amount)

  return true
end

function M.reset(w)
  w.sim.power.elapsed = 0
end

-- Adds the second clock, hangs the rage on the swing seam and the health hook, and hooks the frame and the reset. The
-- power itself is the player's and travels with it through a reload.
function M.install(w)
  w.sim.power = { elapsed = 0 }
  table.insert(w.sim.seams.swing, onSwing)
  table.insert(w.sim.hooks.frame, M.step)
  table.insert(w.sim.hooks.reset, M.reset)
  Combat.listen(w, "health", function(actor, old)
    onHealth(w, actor, old)
  end)
end

return M
