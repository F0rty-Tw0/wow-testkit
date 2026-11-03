-- Sim mobs over the scenario and the session: s:spawn, s:spawnPack and the session's spawn action.
local A = require("assert")
local H = require("tests.helpers.session")
local SH = require("tests.helpers.sim_combat")

local function test_scenario_spawn_and_spawn_pack_and_a_friendly_mob()
  SH.withSim("retail", function(_, s)
    local boar = s:spawn({ name = "Boar", pos = { x = 0, y = 0 } })
    local pack = s:spawnPack(2)
    local friend = s:spawn({ hostile = false, pos = { x = 0, y = -12 } })
    A.same({ boar.name, #pack, pack[1].pos.x, pack[2].pos.x }, { "Boar", 2, -1.5, 1.5 })
    s:simStep(1)
    A.same({ boar.mobState, friend.mobState, friend.isEnemy }, { "engaged", nil, false })
    A.errors(function()
      s:spawnPack(11)
    end, "n must be a whole number 1-10")
  end)
  local plain = require("scenario").new({ addon = "T", root = "T", flavor = "retail" })
  A.errors(function()
    plain:spawn({})
  end, "needs Scenario.new{sim=...}")
  plain.w:destroy()
end

local function test_session_spawn_action_and_world_reply()
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    local reply = sess:call("sim", { action = "spawn", name = "Boar", pack = 3 })
    local boars = 0
    for _, a in ipairs(reply.world.actors) do
      if a.name == "Boar" then
        boars = boars + 1
      end
    end
    A.same({ reply.ok, boars }, { true, 3 })
    local bad = sess:call("sim", { action = "spawn", pack = 99 })
    A.eq(bad.ok, false)
    A.contains(bad.error, "pack")
    sess:call("sim", { action = "reset" })
    A.eq(#sess:call("sim", { action = "world" }).world.actors, 0)
  end)
end

return function()
  test_scenario_spawn_and_spawn_pack_and_a_friendly_mob()
  test_session_spawn_action_and_world_reply()
end
