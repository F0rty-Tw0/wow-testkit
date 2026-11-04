-- SimEffects over time: persistent areas, Charge, a reload with areas, runs and auras, and a world reset. Every record is a
-- kit literal (tests/helpers/sim_spells.lua).
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local H = require("tests.helpers.session")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SM = require("tests.helpers.sim")
local Sim = require("sim")
local SP = require("tests.helpers.sim_spells")
local SimMelee = require("sim_melee")
local SimSpells = require("sim_spells")
local SimWorld = require("sim_world")

local KIT, OTHER = 900001, 900002
local STOP_Y = -10 + 29 * 25 / 60 -- the 29th frame of a run from y -10 is the first one in melee range of a foe at y 10

local function persistent(id)
  local effect = { type = "persistent", base = 10, target = "areaDest", radius = 8, aura = "periodic" }

  return SP.record({ id = id or KIT, ground = true, duration = 8000, castTime = 0, effects = { effect } })
end

local function test_persistent_area_ticks_each_second_on_the_hostiles_inside()
  SP.withSpells("retail", { persistent() }, function(w, s, player)
    local inside, leaving = SH.foe(w, 0, 10, { health = 1000, healthMax = 1000 }), SH.foe(w, 0, 12, { health = 1000, healthMax = 1000 })
    SimSpells.cast(w, player, KIT, nil, { x = 0, y = 10 })
    s:simStep(0.9)
    A.eq(inside.health, 1000) -- the first tick is a second after the cast
    local ground = SP.effectsOfKind(w, "ground")
    A.same(ground, { { kind = "ground", at = { x = 0, y = 10 }, radius = 8, spellID = KIT } })
    s:simStep(2.6)
    Actors.setPos(w, leaving, 0, 40)
    s:simStep(4.6)
    A.eq(SP.hitsOn(w, "SPELL_PERIODIC_DAMAGE", inside.guid), 8)
    A.eq(SP.hitsOn(w, "SPELL_PERIODIC_DAMAGE", leaving.guid), 3)
    A.eq(inside.health, 920)
    A.same({ #w.sim.areas, #SP.effectsOfKind(w, "ground") }, { 0, 0 })
  end)
end

local function test_persistent_area_survives_a_reload_and_ticks_on_schedule()
  H.withSession({ sim = {} }, function(sess)
    SP.install(sess.w, { persistent() })
    local player = sess.w.sim.player
    local foe = SH.foe(sess.w, 0, 10, { health = 1000, healthMax = 1000 })
    SimSpells.cast(sess.w, player, KIT, nil, { x = 0, y = 10 })
    sess.s:simStep(3.5)
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, { persistent() })
      A.eq(#SP.effectsOfKind(fw, "ground"), 1)
      fresh.s:simStep(4.6)
      A.eq(Actors.get(fw, foe.guid).health, 920) -- 3 ticks before, 5 after: the schedule went on
      A.eq(#fw.sim.areas, 0)
    end)
  end)
end

local function chargeRecord()
  local effects = {
    { type = "charge", base = 0, target = "enemy" },
    { type = "aura", aura = "stun", base = 0, target = "enemy" },
    { type = "energize", base = 9, target = "caster" },
  }

  return SP.record({ minRange = 8, maxRange = 25, duration = 1500, effects = effects })
end

local function test_charge_runs_to_melee_range_then_finishes_the_spell_assumed()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local foe = SP.target(w, player)
    local moves = SM.recordMoves()
    A.eq(SimSpells.cast(w, player, KIT), true)
    A.same({ w.sim.driven, w.sim.charge.guid, w.sim.intents.forward }, { 25, foe.guid, nil }) -- the run never touches the keys
    A.same({ #foe.auras, _G.UnitPower("player", 1) }, { 0, 0 }) -- the rest of the spell waits for the arrival
    s:simStep(0.4)
    SM.near(player.pos.y, 0) -- 10 yd at 25 yd/s
    A.eq(SimMelee.inRange(player, foe), false)
    s:simStep(0.2)
    SM.near(player.pos.y, STOP_Y)
    A.eq(SimMelee.inRange(player, foe), true)
    A.same({ w.sim.driven, w.sim.charge }, { nil, nil })
    A.same(moves, { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" })
    A.eq(foe.auras[1].stun, true)
    A.eq(_G.UnitPower("player", 1), 9)
    s:simStep(1)
    SM.near(player.pos.y, STOP_Y)
    local ran = SP.effectsOfKind(w, "charge")[1]
    A.same({ ran.from, ran.to, ran.spellID }, { { x = 0, y = -10 }, { x = 0, y = 10 }, KIT })
  end)
end

local function test_charge_cancelled_by_the_death_of_its_target_finishes_nothing()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    s:simStep(0.2)
    Resolve.kill(w, foe)
    s:simStep(0.2)
    A.same({ w.sim.driven, w.sim.charge, _G.UnitPower("player", 1) }, { nil, nil, 0 })
    A.eq(SP.hitsOn(w, "SPELL_AURA_APPLIED", foe.guid), 0)
  end)
end

local function test_charge_turns_to_face_a_foe_that_is_off_to_the_side()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local foe = SP.target(w, player, 0, 10)
    SimSpells.cast(w, player, KIT)
    Actors.setPos(w, foe, 20, -10) -- the foe moves; the run follows it
    s:simStep(1.5)
    A.eq(SimMelee.inRange(player, foe), true)
  end)
end

local function test_charge_cancelled_by_the_death_of_the_player_finishes_nothing()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    s:simStep(0.2)
    Resolve.kill(w, player)
    s:simStep(0.5)
    A.same({ w.sim.driven, w.sim.charge, _G.UnitPower("player", 1), #foe.auras }, { nil, nil, 0, 0 })
  end)
end

local function test_charge_cancelled_by_a_stun_on_the_player_finishes_nothing_assumed()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    s:simStep(0.2)
    local stoppedAt = player.pos.y
    Auras.apply(w, player, { spellID = 1, stun = true })
    s:simStep(0.5)
    A.same({ w.sim.driven, w.sim.charge, _G.UnitPower("player", 1), #foe.auras }, { nil, nil, 0, 0 })
    SM.near(player.pos.y, stoppedAt)
  end)
end

local function test_charge_faces_the_foe_again_every_frame()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local foe = SP.target(w, player, 0, 10)
    SimSpells.cast(w, player, KIT)
    A.eq(player.facing, 0, "the foe is dead ahead")
    Actors.setPos(w, foe, 20, player.pos.y) -- due east of the player now
    s:simStep(1 / 60)
    SM.near(player.facing, 3 * math.pi / 2)
  end)
end

-- Casts Charge at a foe 20 yd ahead, lets run(s) press keys 6 frames in, and steps to the frame of the arrival (the 29th).
local function chargeAt(w, s, player, run)
  local foe = SP.target(w, player)
  SimSpells.cast(w, player, KIT)
  s:simStep(6 / 60)
  run(s)
  s:simStep(23 / 60)

  return foe
end

local function assertArrived(w, player, foe)
  SM.near(player.pos.y, STOP_Y)
  A.same({ foe.auras[1] and foe.auras[1].stun, _G.UnitPower("player", 1), w.sim.charge, w.sim.driven }, { true, 9, nil, nil })
end

local function test_a_key_tap_mid_run_does_not_stall_the_charge()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local foe = chargeAt(w, s, player, function(keys)
      keys:key("W", "down")
      keys:simStep(0.05)
      keys:key("W", "up")
    end)
    assertArrived(w, player, foe)
    s:key("W", "down")
    s:simStep(0.1)
    A.eq(w.sim.speed, 7, "the next walk runs at the run pace")
  end)
end

local function test_a_held_back_key_mid_run_does_not_stall_the_charge()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local foe = chargeAt(w, s, player, function(keys)
      keys:key("S", "down")
    end)
    assertArrived(w, player, foe)
    s:simStep(0.1)
    A.eq(w.sim.speed, 4.5, "the held key walks the player back after the run")
  end)
end

local function test_a_held_forward_key_keeps_walking_after_the_arrival()
  SP.withSpells("retail", { chargeRecord() }, function(w, s, player)
    local moves = SM.recordMoves()
    s:key("W", "down")
    local foe = chargeAt(w, s, player, function() end)
    assertArrived(w, player, foe)
    s:simStep(0.1)
    A.same({ w.sim.intents.forward, w.sim.speed }, { true, 7 })
    A.same(moves, { "PLAYER_STARTED_MOVING" })
  end)
end

local function test_a_foe_out_of_reach_ends_the_run_at_the_deadline_assumed()
  local rec = chargeRecord()
  rec.maxRange = 100
  SP.withSpells("retail", { rec }, function(w, s, player)
    local foe = SP.target(w, player, 0, 60)
    local moves = SM.recordMoves()
    SimSpells.cast(w, player, KIT)
    s:simStep(2)
    A.eq(math.abs(player.pos.y - (-10 + 25 * 1.5)) < 0.5, true, "1.5 s at 25 yd/s")
    A.same({ w.sim.charge, w.sim.driven, #foe.auras, _G.UnitPower("player", 1) }, { nil, nil, 0, 0 })
    A.same(moves, { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" })
  end)
end

local function test_a_reload_drops_the_charge_and_stops_the_run()
  H.withSession({ sim = {} }, function(sess)
    SP.install(sess.w, { chargeRecord() })
    SP.target(sess.w, sess.w.sim.player)
    SimSpells.cast(sess.w, sess.w.sim.player, KIT)
    sess.s:simStep(0.2)
    SH.reloaded(sess, function(fresh)
      fresh.s:simStep(0.5)
      local fw = fresh.w
      A.same({ fw.sim.charge, fw.sim.driven, fw.sim.intents.forward, fw.sim.moving }, { nil, nil, nil, false })
    end)
  end)
end

local function test_reset_clears_the_charge_the_areas_and_the_ring()
  SP.withSpells("retail", { chargeRecord(), persistent(OTHER) }, function(w, s, player)
    SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    SimSpells.cast(w, player, OTHER, nil, { x = 0, y = 10 })
    s:simStep(0.1)
    A.same({ #w.sim.areas, #SimWorld.build(w).effects > 0 }, { 1, true })
    Sim.reset(w)
    A.same({ w.sim.charge, w.sim.driven, #w.sim.areas }, { nil, nil, 0 })
    A.same(SimWorld.build(w).effects, {})
  end)
end

local function test_an_aura_survives_a_reload_and_is_logged_when_it_ends()
  local rec = SP.record({ duration = 8000, effects = { { type = "aura", aura = "stun", target = "enemy" } } })
  H.withSession({ sim = {} }, function(sess)
    SP.install(sess.w, { rec })
    local foe = SP.target(sess.w, sess.w.sim.player)
    SimSpells.cast(sess.w, sess.w.sim.player, KIT)
    sess.s:simStep(2)
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      A.same(SP.effectsOfKind(fw, "aura"), { { kind = "aura", guid = foe.guid, spellID = KIT, style = "stun" } })
      fresh.s:simStep(6.2)
      A.eq(#Actors.get(fw, foe.guid).auras, 0)
      A.eq(SP.hitsOn(fw, "SPELL_AURA_REMOVED", foe.guid), 1)
      A.same(fw.sim.spellAuras, {})
    end)
  end)
end

return function()
  test_persistent_area_ticks_each_second_on_the_hostiles_inside()
  test_persistent_area_survives_a_reload_and_ticks_on_schedule()
  test_charge_runs_to_melee_range_then_finishes_the_spell_assumed()
  test_charge_cancelled_by_the_death_of_its_target_finishes_nothing()
  test_charge_turns_to_face_a_foe_that_is_off_to_the_side()
  test_charge_cancelled_by_the_death_of_the_player_finishes_nothing()
  test_charge_cancelled_by_a_stun_on_the_player_finishes_nothing_assumed()
  test_charge_faces_the_foe_again_every_frame()
  test_a_key_tap_mid_run_does_not_stall_the_charge()
  test_a_held_back_key_mid_run_does_not_stall_the_charge()
  test_a_held_forward_key_keeps_walking_after_the_arrival()
  test_a_foe_out_of_reach_ends_the_run_at_the_deadline_assumed()
  test_a_reload_drops_the_charge_and_stops_the_run()
  test_reset_clears_the_charge_the_areas_and_the_ring()
  test_an_aura_survives_a_reload_and_is_logged_when_it_ends()
end
