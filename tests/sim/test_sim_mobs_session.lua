-- Sim mobs over the scenario and the session: s:spawn, s:spawnPack and the session's spawn action.
local A = require("assert")
local H = require("tests.helpers.session")
local Scenario = require("scenario")
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
  local plain = Scenario.new({ addon = "T", root = "T", flavor = "retail" })
  local ok, err = pcall(function()
    A.errors(function()
      plain:spawn({})
    end, "needs Scenario.new{sim=...}")
  end)
  plain.w:destroy()
  if not ok then
    error(err, 0)
  end
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

local function test_session_spawn_refuses_a_bad_mob_before_adding_anything()
  local BAD = {
    { { ai = "x" }, "ai must be a table or false" },
    { { ai = { swing = "x" } }, "ai.swing" },
    { { ai = { swing = { damage = 3 } } }, "ai.swing" },
    { { ai = { swing = { every = 2 } } }, "ai.swing.damage" },
    { { ai = { spells = { { every = 0 } } } }, "ai.spells" },
    { { level = 0 }, "level" },
    { { health = -5 }, "health" },
    { { pack = 2, name = 5 }, "name must be a string" },
  }
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    for _, case in ipairs(BAD) do
      local req = { action = "spawn" }
      for key, value in pairs(case[1]) do
        req[key] = value
      end
      local reply = sess:call("sim", req)
      A.same({ reply.ok, string.find(reply.error, case[2], 1, true) ~= nil }, { false, true }, case[2])
      A.eq(string.find(reply.error, ".lua:", 1, true), nil, reply.error) -- no file path leaks through the session
      A.eq(#sess:call("sim", { action = "world" }).world.actors, 0, case[2])
    end
    A.eq(sess:call("sim", { action = "step", seconds = 0.25 }).ok, true)
  end)
end

local function test_session_pack_rule_lives_in_sim_mobs()
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    for _, bad in ipairs({ 0, 11, 1.5, "x" }) do
      local reply = sess:call("sim", { action = "spawn", pack = bad })
      A.same({ reply.ok, string.find(reply.error, "SimMobs.pack: n must be a whole number 1-10", 1, true) ~= nil }, { false, true })
    end
  end)
end

return function()
  test_scenario_spawn_and_spawn_pack_and_a_friendly_mob()
  test_session_spawn_action_and_world_reply()
  test_session_spawn_refuses_a_bad_mob_before_adding_anything()
  test_session_pack_rule_lives_in_sim_mobs()
end
