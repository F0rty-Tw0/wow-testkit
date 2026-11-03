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

return function()
  test_a_dead_player_stops_attacking_and_cannot_start()
end
