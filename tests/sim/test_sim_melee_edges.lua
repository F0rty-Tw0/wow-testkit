local A = require("assert")
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

return function()
  test_a_dead_player_stops_attacking_and_cannot_start()
  test_a_long_out_of_range_streak_does_not_bank_swings()
  test_out_of_range_and_behind_reports_the_range_error()
  test_start_attack_with_a_unit_targets_it_first()
end
