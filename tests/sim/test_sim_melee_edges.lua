local A = require("assert")
local Auras = require("combat_auras")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SimMelee = require("sim_melee")
local SimTarget = require("sim_target")

local function swingCount(player)
  return player.swings or 0
end

local function engageAt(w, y)
  local foe = SH.foe(w, 0, y, { health = 1000, healthMax = 1000 })
  SimTarget.target(w, foe)

  return foe
end

local function test_a_dead_player_stops_attacking_and_cannot_start()
  SH.withSim("retail", function(w, s, player)
    engageAt(w, -2)
    SimMelee.start(w)
    s:simStep(0.1)
    A.eq(swingCount(player), 1)
    Resolve.kill(w, player)
    s:simStep(10)
    A.same({ w.sim.melee.on, swingCount(player) }, { false, 1 })
    A.eq(SimMelee.start(w), false)
    A.eq(w.sim.melee.on, false)
  end)
end

local function test_a_long_out_of_range_streak_does_not_bank_swings()
  SH.withSim("retail", function(w, s, player)
    local speed = SimMelee.weapon(player).speed
    engageAt(w, 10) -- centre 20 -> 17: out of range
    SimMelee.start(w)
    for _ = 1, 8 do
      s:simStep(0.5) -- a 4 s streak, longer than one swing speed
    end
    s:place(0, 2) -- centre 8 -> 5
    s:simStep(0.1)
    A.eq(swingCount(player), 1)
    s:simStep(0.1)
    A.eq(swingCount(player), 1) -- the next swing waits for the speed, not for the banked streak
    s:simStep(speed)
    A.eq(swingCount(player), 2)
  end)
end

local function test_out_of_range_and_behind_reports_the_range_error()
  SH.withSim("retail", function(w, s)
    engageAt(w, -30) -- centre 20 -> 17 and behind the north-facing player
    local errors = SH.record(w, { "UI_ERROR_MESSAGE" })
    SimMelee.start(w)
    s:simStep(0.5)
    A.same({ #errors, errors[1][4] }, { 1, _G.ERR_BADATTACKPOS })
  end)
end

local function test_start_attack_with_a_unit_targets_it_first()
  SH.withSim("retail", function(w)
    engageAt(w, -2)
    local hovered = SH.foe(w, 0, -2, { health = 1000, healthMax = 1000 })
    SimTarget.hover(w, hovered)
    _G.StartAttack("mouseover")
    A.same({ w.sim.player.targetGuid, w.sim.melee.targetGuid, w.sim.melee.on }, { hovered.guid, hovered.guid, true })
  end)
end

-- The swing seam: every function of w.sim.seams.swing runs (w, attacker, target, spec) before the damage and again with
-- spec.landed = true after a swing that landed; the first call may set spec.miss.
local function watchSeam(w, calls)
  table.insert(w.sim.seams.swing, function(world, attacker, target, spec)
    calls[#calls + 1] = { world = world, attacker = attacker, target = target, landed = spec.landed, amount = spec.amount }
    calls[#calls].health = target.health
  end)
end

local function test_a_swing_calls_the_swing_seam_before_the_damage_and_again_after_it_landed()
  SH.withSim("retail", function(w, s, player)
    local foe = engageAt(w, -2)
    local calls = {}
    watchSeam(w, calls)
    SimMelee.start(w)
    s:simStep(0.1)
    A.eq(#calls, 2)
    A.same({ calls[1].world == w, calls[1].attacker == player, calls[1].target == foe }, { true, true, true })
    A.same({ calls[1].landed, calls[1].amount, calls[1].health }, { nil, 8, 1000 })
    A.same({ calls[2].landed, calls[2].amount, calls[2].health }, { true, 8, 992 })
  end)
end

local function test_a_seam_that_sets_a_miss_turns_the_swing_into_a_logged_miss()
  SH.withSim("retail", function(w, s, player)
    local foe = engageAt(w, -2)
    local calls = {}
    table.insert(w.sim.seams.swing, function(_, _, _, spec)
      spec.miss = spec.landed == nil and "DODGE" or nil
    end)
    watchSeam(w, calls)
    SimMelee.start(w)
    s:simStep(0.1)
    local missed
    for _, entry in ipairs(w.combat.log.entries) do
      missed = missed or (entry[2] == "SWING_MISSED" and entry[4] == player.guid)
    end
    A.same({ missed, foe.health, swingCount(player), #calls, w.sim.melee.timer > 1 }, { true, 1000, 0, 1, true })
  end)
end

local function test_a_swing_the_target_is_immune_to_never_reaches_the_landed_call()
  SH.withSim("retail", function(w, s)
    local foe = engageAt(w, -2)
    Auras.apply(w, foe, { spellID = 900004, immune = true })
    local calls = {}
    watchSeam(w, calls)
    SimMelee.start(w)
    s:simStep(0.1)
    A.same({ #calls, calls[1].landed }, { 1, nil })
  end)
end

local function test_a_world_without_the_seams_swings_as_before()
  SH.withSim("retail", function(w, s, player)
    engageAt(w, -2)
    w.sim.seams = nil
    SimMelee.start(w)
    s:simStep(0.1)
    A.eq(swingCount(player), 1)
  end)
end

return function()
  test_a_dead_player_stops_attacking_and_cannot_start()
  test_a_long_out_of_range_streak_does_not_bank_swings()
  test_out_of_range_and_behind_reports_the_range_error()
  test_start_attack_with_a_unit_targets_it_first()
  test_a_swing_calls_the_swing_seam_before_the_damage_and_again_after_it_landed()
  test_a_seam_that_sets_a_miss_turns_the_swing_into_a_logged_miss()
  test_a_swing_the_target_is_immune_to_never_reaches_the_landed_call()
  test_a_world_without_the_seams_swings_as_before()
end
