-- SimPower: the player's rage (landed swings and damage taken up, decay out of combat) and mana (a tick a second), the cost a
-- cast pays, and the power events. Every record is a kit literal (tests/helpers/sim_spells.lua); no extract is read.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.session")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SP = require("tests.helpers.sim_spells")
local SimMelee = require("sim_melee")
local SimPower = require("sim_power")
local SimSpells = require("sim_spells")
local State = require("combat_state")

local RAGE_SPELL = 900001
local PERHIT = SimPower.RAGE.perHit

-- A foe 1 yard ahead of the player (at (0, -10), facing north) that becomes its target.
local function foeAhead(w, player)
  local foe = SH.foe(w, 0, -9)
  Actors.setTarget(w, player, foe)

  return foe
end

local function test_rage_comes_from_landed_swings_and_damage_taken()
  SH.withSim("retail", function(w, s, player)
    local foe = foeAhead(w, player)
    A.eq(player.powerMax, SimPower.RAGE.max)
    SimMelee.start(w)
    s:simStep(0.1)
    A.eq(_G.UnitPower("player", 1), PERHIT)
    Resolve.damage(w, foe, player, { amount = 40 })
    A.eq(_G.UnitPower("player", 1), PERHIT + 10, "25 * 40 / 100 for a player of 100 health")
  end)
end

local function test_the_blow_that_kills_the_player_pays_no_rage()
  SH.withSim("retail", function(w, _, player)
    Resolve.kill(w, player)
    A.same({ player.isDead, player.power }, { true, 0 })
  end)
end

local function test_a_swing_that_does_not_land_pays_no_rage()
  SH.withSim("retail", function(w, s, player)
    foeAhead(w, player)
    table.insert(w.sim.seams.swing, function(_, _, _, spec)
      spec.miss = "DODGE"
    end)
    SimMelee.start(w)
    s:simStep(0.1)
    A.same({ player.swings or 0, player.power }, { 0, 0 })
  end)
end

local function test_rage_decays_only_out_of_combat_and_stops_at_zero()
  SH.withSim("retail", function(w, s, player)
    local foe = foeAhead(w, player)
    Resolve.damage(w, foe, player, { amount = 40 })
    A.same({ player.power, player.affectingCombat }, { 10, true })
    s:simStep(4)
    A.eq(player.power, 10, "no decay while the player fights")
    Resolve.kill(w, foe)
    s:simStep(10)
    A.eq(player.affectingCombat, false)
    A.eq(player.power < 10 and player.power >= 0, true)
    s:simStep(30)
    A.eq(player.power, 0)
  end)
end

local function test_rage_stops_at_the_maximum()
  SH.withSim("retail", function(w, s, player)
    foeAhead(w, player)
    Actors.setPower(w, player, 98)
    SimMelee.start(w)
    s:simStep(0.1)
    A.eq(player.power, 100)
    Actors.setPower(w, player, 99)
    Resolve.damage(w, SH.foe(w, 0, 30), player, { amount = 90 })
    A.eq(player.power, 100)
  end)
end

local function test_a_mage_gains_mana_a_tick_a_second_and_no_rage()
  SH.withSim("retail", function(w, s, player)
    foeAhead(w, player)
    Actors.setPower(w, player, 0)
    s:simStep(3)
    A.eq(player.power, 3 * SimPower.MANA.regen * player.powerMax)
    Actors.setPower(w, player, 99)
    s:simStep(5)
    A.eq(player.power, 100)
    Actors.setPower(w, player, 0)
    SimMelee.start(w)
    s:simStep(0.1)
    A.eq(player.power, 0, "a landed swing pays rage only to a rage user")
  end, { class = "MAGE" })
end

local function test_power_events_fire_once_per_change()
  SH.withSim("retail", function(w, s, player)
    local foe = foeAhead(w, player)
    local log = SH.record(w, { "UNIT_POWER_UPDATE" })
    SimMelee.start(w)
    s:simStep(0.1)
    SimMelee.stop(w)
    A.same({ #log, log[1][3], log[1][4] }, { 1, "player", "RAGE" })
    Resolve.damage(w, foe, player, { amount = 40 })
    A.eq(#log, 2)
    Actors.setPower(w, player, 100)
    s:simStep(30)
    A.eq(#log, 3, "a tick that changes nothing fires nothing")
  end)
end

local function test_spend_takes_the_cost_or_refuses_with_the_power_error()
  SH.withSim("retail", function(w, _, player)
    Actors.setPower(w, player, 30)
    local errors = SH.record(w, { "UI_ERROR_MESSAGE" })
    A.eq(SimPower.spend(w, player, "RAGE", 20), true)
    A.same({ player.power, #errors }, { 10, 0 })
    A.eq(SimPower.spend(w, player, "RAGE", 20), false)
    A.same({ player.power, #errors, errors[1][4] }, { 10, 1, _G.ERR_OUT_OF_RAGE })
    A.eq(SimPower.spend(w, player, "MANA", 1), false)
    A.same({ player.power, #errors, errors[2][4] }, { 10, 2, _G.ERR_OUT_OF_MANA })
  end)
end

local function test_an_instant_cast_pays_its_cost()
  local rec = SP.record({ id = RAGE_SPELL, cost = { type = "RAGE", amount = 20 } })
  SP.withSpells("retail", { rec }, function(w, _, player)
    Actors.setPower(w, player, 50)
    A.eq(SimSpells.cast(w, player, RAGE_SPELL, SP.target(w, player)), true)
    A.eq(player.power, 30)
    Actors.setPower(w, player, 10)
    A.same({ SimSpells.cast(w, player, RAGE_SPELL) }, { false, "ERR_OUT_OF_RAGE" })
    A.eq(player.power, 10)
  end)
end

local function test_a_timed_cast_pays_when_the_bar_ends_and_fails_if_the_power_is_gone_by_then()
  local rec = SP.record({
    id = RAGE_SPELL,
    castTime = 2000,
    cost = { type = "RAGE", amount = 20 },
    effects = { { type = "damage", base = 7, target = "enemy" } },
  })
  SP.withSpells("retail", { rec }, function(w, s, player)
    local foe = SP.target(w, player)
    State.engage(w, foe, player)
    Actors.setPower(w, player, 50)
    SimSpells.cast(w, player, RAGE_SPELL)
    s:simStep(1)
    A.same({ player.power, foe.health }, { 50, 100 })
    s:simStep(1.2)
    A.eq(player.power, 30)
    s:simStep(1)
    A.eq(foe.health < 100, true, "the effects land after the cost")
    Actors.setPower(w, player, 50)
    s:simStep(2)
    SimSpells.cast(w, player, RAGE_SPELL)
    s:simStep(0.5)
    Actors.setPower(w, player, 5)
    local errors = SH.record(w, { "UI_ERROR_MESSAGE" })
    local ends = SH.record(w, { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED" })
    local health = foe.health
    s:simStep(4)
    A.same({ player.power, foe.health, #errors, errors[1][4] }, { 5, health, 1, _G.ERR_OUT_OF_RAGE })
    A.same({ #ends, ends[1].event, player.casting }, { 1, "UNIT_SPELLCAST_INTERRUPTED", nil })
  end)
end

local function test_rage_survives_a_reload()
  H.withSession({ sim = {} }, function(sess)
    Actors.setPower(sess.w, sess.w.sim.player, 42)
    SH.reloaded(sess, function(fresh)
      A.eq(fresh.w.sim.player.power, 42)
      fresh.s:simStep(1)
      A.eq(fresh.w.sim.player.power, 41, "out of combat the decay goes on")
    end)
  end)
end

return function()
  test_rage_comes_from_landed_swings_and_damage_taken()
  test_the_blow_that_kills_the_player_pays_no_rage()
  test_a_swing_that_does_not_land_pays_no_rage()
  test_rage_decays_only_out_of_combat_and_stops_at_zero()
  test_rage_stops_at_the_maximum()
  test_a_mage_gains_mana_a_tick_a_second_and_no_rage()
  test_power_events_fire_once_per_change()
  test_spend_takes_the_cost_or_refuses_with_the_power_error()
  test_an_instant_cast_pays_its_cost()
  test_a_timed_cast_pays_when_the_bar_ends_and_fails_if_the_power_is_gone_by_then()
  test_rage_survives_a_reload()
end
