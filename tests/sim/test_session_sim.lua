-- Session sim: the sim method (step, world, reset) over sess:call, the world reply it builds, input over the wire against
-- a sim world, and the two guards that keep the sim clock the only clock.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.session")
local Near = require("tests.helpers.sim")
local Session = require("session")

local function withSim(fn)
  H.withSession({ sim = {} }, fn)
end

local function sim(sess, req)
  return sess:call("sim", req)
end

local function walkNorth(sess)
  local down = sess:call("input", { kind = "keydown", key = "W" })
  A.eq(down.ok, true, down.error)
  for _ = 1, 4 do
    sim(sess, { action = "step", seconds = 0.25 })
  end
end

local function test_world_reads_the_fresh_player()
  withSim(function(sess)
    local seq = sess.seq
    local r = sim(sess, { action = "world" })
    A.same(
      { r.ok, r.world.player.pos, r.world.player.facing, r.world.player.class, r.world.player.swings, r.world.player.moving },
      { true, { x = 0, y = -10 }, 0, "WARRIOR", 0, false }
    )
    A.same(r.world.actors, {})
    A.same(r.world.effects, {})
    A.eq(sess.seq, seq, "a read")
    A.contains(sess:handle("sim", { action = "world" }), '"actors":[]')
  end)
end

local function test_world_player_reports_health_and_power()
  withSim(function(sess)
    local player = sim(sess, { action = "world" }).world.player
    A.same({ player.health, player.healthMax, player.power, player.powerMax }, { 100, 100, 0, 100 })
    A.eq(type(player.guid), "string")
  end)
end

local function test_keydown_walks_and_keyup_stops()
  withSim(function(sess)
    local seq = sess.seq
    local down = sess:call("input", { kind = "keydown", key = "W" })
    A.same({ down.ok, down.binding }, { true, "MOVEFORWARD" })
    A.eq(sess.seq, seq + 1)
    seq = sess.seq
    for _ = 1, 4 do
      sim(sess, { action = "step", seconds = 0.25 })
    end
    local player = sim(sess, { action = "world" }).world.player
    Near.near(player.pos.y, -3)
    A.eq(player.moving, true)
    A.truthy(sess.seq > seq, "steps change the world")
    sess:call("input", { kind = "keyup", key = "W", mods = { shift = true } })
    A.eq(sess.w.sim.intents.forward, nil)
  end)
end

local function test_keyup_of_a_key_never_held_changes_nothing()
  withSim(function(sess)
    local seq = sess.seq
    local up = sess:call("input", { kind = "keyup", key = "W" })
    A.eq(up.ok, true)
    A.eq(sess.seq, seq)
  end)
end

local function test_keydown_needs_a_string_key()
  withSim(function(sess)
    local r = sess:call("input", { kind = "keydown", key = 5 })
    A.same({ r.ok, r.error }, { false, "input: key must be a string for keydown" })
  end)
end

local function test_step_refuses_a_bad_length()
  withSim(function(sess)
    for _, seconds in ipairs({ 0.3, 0, -1, "x", 1 / 0 }) do
      local r = sim(sess, { action = "step", seconds = seconds })
      A.eq(r.ok, false)
      A.contains(r.error, "sim: seconds must be a number above 0 and at most 0.25", tostring(seconds))
    end
  end)
end

local function test_unknown_action_lists_the_valid_ones()
  withSim(function(sess)
    local r = sim(sess, { action = "dance" })
    A.same({ r.ok, r.error }, { false, "sim: unknown action 'dance'; valid: reset, step, world" })
  end)
end

local function test_step_runs_an_onupdate_under_the_engine_context()
  withSim(function(sess)
    local seen = {}
    local frame = _G.CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(_, elapsed)
      seen.base = sess.w.stack[1]
      seen.elapsed = elapsed
    end)
    local r = sim(sess, { action = "step", seconds = 0.1 })
    A.same({ r.ok, seen.base, seen.elapsed }, { true, "blizzard", 0.1 })
    A.same(sess.w.errors, {})
  end)
end

local function test_world_lists_actors_in_spawn_order()
  withSim(function(sess)
    local w = sess.w
    local player = w.sim.player
    local npc = Actors.add(w, { kind = "npc", name = "Wolf", hostile = true, pos = { x = 5, y = 5 } })
    local pal = Actors.add(w, { kind = "npc", name = "Pal", pos = { x = 1, y = 1 } })
    npc.auras[1] = { spellId = 900004 }
    pal.lootable = true
    Actors.setTarget(w, player, npc)
    Actors.bind(w, npc, "mouseover")
    local actors = sim(sess, { action = "world" }).world.actors
    A.same({ #actors, actors[1].name, actors[2].name }, { 2, "Wolf", "Pal" })
    local wolf = actors[1]
    A.same(
      { wolf.isTarget, wolf.isMouseover, wolf.auras, wolf.class, wolf.swings, wolf.hostile, wolf.lootable, wolf.dead },
      { true, true, { 900004 }, nil, 0, true, false, false }
    )
    A.same({ wolf.pos, wolf.facing, wolf.health, wolf.healthMax, wolf.kind }, { { x = 5, y = 5 }, 0, 100, 100, "npc" })
    A.same({ actors[2].isTarget, actors[2].lootable, actors[2].hostile }, { false, true, false })
  end)
end

local function test_reset_returns_the_player_to_the_spawn()
  withSim(function(sess)
    local w = sess.w
    local npc = Actors.add(w, { kind = "npc", name = "Wolf", hostile = true, pos = { x = 5, y = 5 } })
    local pal = Actors.add(w, { kind = "npc", name = "Pal", pos = { x = 1, y = 1 } })
    pal.inParty = true
    Actors.setTarget(w, w.sim.player, npc)
    Actors.setHealth(w, w.sim.player, 40)
    walkNorth(sess)
    sess:call("input", { kind = "keyup", key = "W" })
    w.sim.intents.strafeLeft = true
    local seq = sess.seq
    local r = sim(sess, { action = "reset" })
    A.eq(r.ok, true, r.error)
    A.eq(sess.seq, seq + 1)
    A.same({ #r.world.actors, r.world.actors[1].name }, { 1, "Pal" })
    A.same({ r.world.player.pos, r.world.player.health, r.world.player.moving }, { { x = 0, y = -10 }, 100, false })
    A.same({ w.sim.player.targetGuid, w.sim.intents }, { nil, {} })
  end)
end

local function test_reset_with_a_class_changes_the_class()
  withSim(function(sess)
    local r = sim(sess, { action = "reset", class = "MAGE" })
    A.same({ r.ok, r.world.player.class, r.world.player.power, (_G.UnitClass("player")) }, { true, "MAGE", 100, "Mage" })
    local bad = sim(sess, { action = "reset", class = "X" })
    A.eq(bad.ok, false)
    A.contains(bad.error, "class must be")
  end)
end

local function test_a_refused_class_leaves_the_world_alone()
  withSim(function(sess)
    local npc = Actors.add(sess.w, { kind = "npc", name = "Wolf", hostile = true, pos = { x = 5, y = 5 } })
    sim(sess, { action = "reset", class = "X" })
    A.eq(Actors.get(sess.w, npc.guid), npc)
  end)
end

local function test_reset_runs_the_reset_hooks_under_the_engine_context()
  withSim(function(sess)
    local seen = {}
    table.insert(sess.w.sim.hooks.reset, function(w)
      seen.base, seen.sameWorld = w.stack[1], w == sess.w
    end)
    sim(sess, { action = "reset" })
    A.same({ seen.base, seen.sameWorld }, { "blizzard", true })
  end)
end

local function test_combat_step_and_advance_obey_the_sim_clock()
  withSim(function(sess)
    local r = sess:call("combat", { action = "step", seconds = 1 })
    A.same({ r.ok, r.error }, { false, "sim clock owns time" })
    local before = _G.GetTime()
    local slash = sess:call("slash", { text = "/advance 1" })
    A.eq(slash.ok, true, slash.error)
    Near.near(_G.GetTime() - before, 1, "advance moved the sim clock by 1")
  end)
end

local function test_a_session_without_the_sim_refuses_the_method()
  H.withSession(nil, function(sess)
    local r = sess:call("sim", { action = "world" })
    A.eq(r.ok, false)
    A.contains(r.error, "sim: this session was opened without the sim (start it with --sim)")
  end)
end

local function test_a_session_opens_with_the_class_it_is_given()
  H.withSession({ sim = { class = "MAGE" } }, function(sess)
    A.eq(sim(sess, { action = "world" }).world.player.class, "MAGE")
  end)
end

local function test_a_reload_keeps_the_sim()
  withSim(function(sess)
    local fresh = Session.reload(sess)
    local ok, err = pcall(function()
      A.eq(fresh:call("sim", { action = "world" }).ok, true)
      A.eq(_G.GetBindingAction("W"), "MOVEFORWARD")
    end)
    fresh:shutdown()
    A.eq(ok, true, err)
  end)
end

return function()
  test_world_reads_the_fresh_player()
  test_world_player_reports_health_and_power()
  test_keydown_walks_and_keyup_stops()
  test_keyup_of_a_key_never_held_changes_nothing()
  test_keydown_needs_a_string_key()
  test_step_refuses_a_bad_length()
  test_unknown_action_lists_the_valid_ones()
  test_step_runs_an_onupdate_under_the_engine_context()
  test_world_lists_actors_in_spawn_order()
  test_reset_returns_the_player_to_the_spawn()
  test_reset_with_a_class_changes_the_class()
  test_a_refused_class_leaves_the_world_alone()
  test_reset_runs_the_reset_hooks_under_the_engine_context()
  test_combat_step_and_advance_obey_the_sim_clock()
  test_a_session_without_the_sim_refuses_the_method()
  test_a_session_opens_with_the_class_it_is_given()
  test_a_reload_keeps_the_sim()
end
