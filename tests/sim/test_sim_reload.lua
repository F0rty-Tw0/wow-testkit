-- Sim reload: Session.reload keeps a sim world (place, actors, auras, combat, group, class, walk, clock) through
-- Sim.export and Sim.restore; a toggled sim or a changed flavor opens a fresh one; the export is plain data.
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local Cast = require("combat_cast")
local CombatH = require("tests.helpers.combat")
local Group = require("combat_group")
local H = require("tests.helpers.session")
local Json = require("json")
local Log = require("combat_log")
local Near = require("tests.helpers.sim")
local Session = require("session")
local Sim = require("sim")
local State = require("combat_state")

local SPAWN = { x = 0, y = -10 }

local function withSim(fn, opts)
  local merged = { sim = {} }
  for key, value in pairs(opts or {}) do
    merged[key] = value
  end
  H.withSession(merged, fn)
end

-- Reloads sess with over and runs fn(fresh); fresh is always shut down.
local function reloaded(sess, over, fn)
  local fresh, failure = Session.reload(sess, over)
  A.eq(failure, nil, failure)
  local ok, err = pcall(fn, fresh)
  fresh:shutdown()
  if not ok then
    error(err, 0)
  end
end

-- Brute: a hostile npc at (5, 5) with 40 of 100 health and a 10 s aura, the player's target and foe.
local function brute(w)
  local actor = Actors.add(w, { kind = "npc", name = "Brute", hostile = true, pos = { x = 5, y = 5 }, health = 40, healthMax = 100 })
  Auras.apply(w, actor, { spellID = 900004, duration = 10 })
  Actors.setTarget(w, w.sim.player, actor)
  State.engage(w, actor, w.sim.player)

  return actor
end

local function test_the_world_survives_a_reload()
  for _, flavor in ipairs(Near.FLAVORS) do
    withSim(function(sess)
      local w, s = sess.w, sess.s
      s:place(12, 3)
      s:face(1)
      Actors.remove(w, Actors.add(w, { kind = "npc", name = "Gone" }))
      local old = brute(w)
      Actors.bind(w, old, "mouseover")
      s:simStep(4)
      local before, stamp = _G.GetTime(), Log.timestamp(w)
      reloaded(sess, nil, function(fresh)
        local fw = fresh.w
        local player = fw.sim.player
        A.same({ player.pos, player.facing }, { { x = 12, y = 3 }, 1 }, flavor)
        local kept = Actors.get(fw, old.guid)
        A.same({ kept.guid, kept.name, kept.health, kept.pos }, { old.guid, "Brute", 40, { x = 5, y = 5 } }, flavor)
        Near.near(kept.auras[1].expirationTime - _G.GetTime(), 6, flavor .. " aura left")
        A.same({ player.targetGuid, _G.UnitGUID("mouseover"), _G.InCombatLockdown() }, { old.guid, old.guid, true }, flavor)
        A.same(fw.errors, {}, flavor .. ": restore raised nothing")
        A.truthy(_G.GetTime() >= before and Log.timestamp(fw) >= stamp, flavor .. ": the clock never goes back")
        local new = Actors.add(fw, { kind = "npc", name = "New" })
        A.truthy(new.guid ~= old.guid and new.guid ~= player.guid, flavor .. ": a new GUID is new")
        fresh.s:simStep(6.1)
        A.eq(#kept.auras, 0, flavor .. ": the aura still expires")
      end)
    end, { flavor = flavor })
  end
end

local function test_a_walk_survives_and_the_viewer_keyup_stops_it()
  withSim(function(sess)
    sess:call("input", { kind = "keydown", key = "W" })
    sess:call("sim", { action = "step", seconds = 0.25 })
    sess:call("sim", { action = "step", seconds = 0.25 })
    local pos = { x = sess.w.sim.player.pos.x, y = sess.w.sim.player.pos.y }
    reloaded(sess, nil, function(fresh)
      A.same({ fresh.w.sim.intents.forward, fresh.w.sim.player.pos }, { true, pos })
      local up = fresh:call("input", { kind = "keyup", key = "W" })
      A.same({ up.ok, up.binding, fresh.w.sim.intents.forward }, { true, "MOVEFORWARD", nil })
    end)
  end)
end

local function test_a_pending_combat_drop_resumes()
  withSim(function(sess)
    local old = brute(sess.w)
    State.disengage(sess.w, old)
    sess.s:simStep(2)
    reloaded(sess, nil, function(fresh)
      local log = CombatH.watch(fresh.w, { "PLAYER_REGEN_ENABLED" })
      fresh.s:simStep(2.9)
      A.same({ _G.InCombatLockdown(), #log }, { true, 0 }, "3 s of the drop were left")
      fresh.s:simStep(0.2)
      A.same({ _G.InCombatLockdown(), #log }, { false, 1 })
    end)
  end)
end

local function test_a_fighting_ai_swings_again_after_the_reload()
  withSim(function(sess)
    local old = brute(sess.w)
    old.ai = { swing = { every = 2, damage = 5 } }
    reloaded(sess, nil, function(fresh)
      local player = fresh.w.sim.player
      fresh.s:simStep(1.9)
      A.eq(player.health, 100)
      fresh.s:simStep(0.2)
      A.eq(player.health, 95, "the swing restarts at its cadence")
    end)
  end)
end

-- Sim.restore straight on a world with a pending timer: the timer keeps its time left and fires on the saved clock.
local function test_pending_timers_keep_their_time_left()
  local state
  Near.withSim("retail", {}, function(w, s)
    s:simStep(30)
    state = Sim.export(w)
  end)
  Near.withSim("retail", { twoPhase = true }, function(w, s)
    local fired
    w:schedule(1, function()
      fired = w.now
    end, 1)
    Sim.restore(w, state)
    Near.near(w.now, state.now, "the clock")
    s:simStep(1.1)
    Near.near(fired, state.now + 1, "the timer")
  end)
end

local function test_a_cast_is_dropped()
  withSim(function(sess)
    Cast.begin(sess.w, sess.w.sim.player, { spellID = 900002, duration = 3 })
    reloaded(sess, nil, function(fresh)
      local log = CombatH.watch(fresh.w, { "UNIT_SPELLCAST_STOP" })
      fresh.s:simStep(3.5)
      A.same({ Actors.get(fresh.w, "player").cast, #log }, { nil, 0 })
    end)
  end)
end

local function test_the_group_survives_and_range_stays_the_sim_distance()
  withSim(function(sess)
    local w = sess.w
    local ann = Actors.add(w, { kind = "player", name = "Ann", pos = { x = 40, y = 40 } })
    Group.set(w, { w.sim.player, ann })
    reloaded(sess, nil, function(fresh)
      A.same({ _G.GetNumGroupMembers(), (_G.UnitName("party1")) }, { 2, "Ann" })
      A.same({ _G.UnitInRange("party1") }, { false, true }, "Ann is 64 yards away")
      fresh.s:place(39, 38)
      A.same({ _G.UnitInRange("party1") }, { true, true }, "Ann is near")
    end)
  end)
end

local function test_the_class_survives_over_the_options()
  withSim(function(sess)
    sess:call("sim", { action = "reset", class = "MAGE" })
    reloaded(sess, nil, function(fresh)
      A.same({ fresh.opts.sim, (_G.UnitClass("player")) }, { {}, "Mage" })
    end)
  end)
end

local function test_toggling_the_sim_opens_a_fresh_world()
  withSim(function(sess)
    sess.s:place(12, 3)
    reloaded(sess, { sim = false }, function(fresh)
      A.same({ fresh.w.sim, sess.simState }, { nil, nil })
      reloaded(fresh, { sim = { class = "MAGE" } }, function(again)
        A.same({ again.w.sim.player.pos, again.w.sim.class, fresh.simState }, { SPAWN, "MAGE", nil })
      end)
    end)
  end)
end

local function test_a_new_flavor_opens_a_fresh_world_and_auto_keeps_it()
  withSim(function(sess)
    sess.s:place(12, 3)
    reloaded(sess, { flavor = "tbc" }, function(fresh)
      A.same(fresh.w.sim.player.pos, SPAWN)
    end)
  end)
  A.eq(Session.autoFlavor(H.DEMO), "retail", "auto picks retail for the demo")
  withSim(function(sess)
    sess.s:place(12, 3)
    reloaded(sess, { flavor = "auto" }, function(fresh)
      A.same(fresh.w.sim.player.pos, { x = 12, y = 3 })
    end)
  end)
end

-- Raises when value holds anything but numbers, strings, booleans and tables, or one table twice.
local function checkPlain(value, seen, path)
  local kind = type(value)
  if kind ~= "table" then
    A.truthy(kind == "number" or kind == "string" or kind == "boolean", path .. " is a " .. kind)
    return
  end
  A.truthy(not seen[value], path .. " is a table seen twice")
  seen[value] = true
  for key, inner in pairs(value) do
    checkPlain(inner, seen, path .. "." .. tostring(key))
  end
end

local function test_the_export_is_plain_data()
  withSim(function(sess)
    local w = sess.w
    local old = brute(w)
    old.ai = { swing = { every = 2, damage = 5 } }
    local ann = Actors.add(w, { kind = "player", name = "Ann", pos = { x = 1, y = 1 } })
    ann.ai = old.ai
    Group.set(w, { w.sim.player, ann })
    Actors.bind(w, old, "mouseover")
    sess:call("input", { kind = "keydown", key = "W" })
    local state = Sim.export(w)
    checkPlain(state, {}, "state")
    A.same({ state.version, state.mouseover, state.held.W, #state.actors }, { 1, old.guid, "MOVEFORWARD", 2 })
    A.truthy(pcall(Json.encode, state), "Json.encode takes it")
  end)
end

local function test_a_bad_sim_option_leaves_the_session_whole()
  withSim(function(sess)
    A.errors(function()
      Session.reload(sess, { sim = "yes" })
    end, "reload: sim")
    A.eq(sess:call("sim", { action = "world" }).ok, true)
  end)
end

-- A unit that persists its state registers on every sim world in its install; Sim.restore stands in for that here.
local function test_persisted_state_comes_back()
  withSim(function(sess)
    local seen
    local spec = {
      export = function()
        return { n = 7 }
      end,
      restore = function(_, data)
        seen = data.n
      end,
    }
    Sim.persist(sess.w, "demo", spec)
    A.eq(Sim.export(sess.w).ext.demo.n, 7)
    local restore = Sim.restore
    Sim.restore = function(w, simState)
      Sim.persist(w, "demo", spec)
      restore(w, simState)
    end
    local ok, err = pcall(reloaded, sess, nil, function() end)
    Sim.restore = restore
    A.eq(ok, true, err)
    A.eq(seen, 7)
  end)
end

return function()
  test_the_world_survives_a_reload()
  test_a_walk_survives_and_the_viewer_keyup_stops_it()
  test_a_pending_combat_drop_resumes()
  test_a_fighting_ai_swings_again_after_the_reload()
  test_pending_timers_keep_their_time_left()
  test_a_cast_is_dropped()
  test_the_group_survives_and_range_stays_the_sim_distance()
  test_the_class_survives_over_the_options()
  test_toggling_the_sim_opens_a_fresh_world()
  test_a_new_flavor_opens_a_fresh_world_and_auto_keeps_it()
  test_the_export_is_plain_data()
  test_a_bad_sim_option_leaves_the_session_whole()
  test_persisted_state_comes_back()
end
