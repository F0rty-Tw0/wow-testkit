-- Sim reload over stale session state: a state request copies the world's combat flag and group into sess.state, and
-- the sim changes both later. The reload takes them from the world, Sim.restore wins over them, and a restore that raises
-- still leaves a session.
local A = require("assert")
local Actors = require("combat_actors")
local Combat = require("combat")
local Group = require("combat_group")
local H = require("tests.helpers.session")
local Session = require("session")
local Sim = require("sim")
local SimH = require("tests.helpers.sim")
local State = require("combat_state")

local SPAWN = { x = 0, y = -10 }

-- Reloads sess and runs fn(fresh); fresh is always shut down.
local function reloaded(sess, fn)
  local fresh, failure = Session.reload(sess, nil)
  A.eq(failure, nil, failure)
  local ok, err = pcall(fn, fresh)
  fresh:shutdown()
  if not ok then
    error(err, 0)
  end
end

local function test_a_combat_the_sim_dropped_stays_dropped_after_a_reload()
  H.withSession({ sim = {} }, function(sess)
    local w = sess.w
    local mob = Actors.add(w, { kind = "npc", name = "Brute", hostile = true, pos = { x = 0, y = 0 } })
    State.engage(w, mob, w.sim.player)
    sess:call("state", { modifiers = { shift = false } })
    State.disengage(w, mob)
    sess.s:simStep(6)
    reloaded(sess, function(fresh)
      A.same({ _G.InCombatLockdown(), fresh.state.combat }, { false, false })
    end)
  end)
end

local function test_a_group_the_sim_cleared_stays_cleared_after_a_reload()
  H.withSession({ sim = {} }, function(sess)
    local w = sess.w
    Group.set(w, { w.sim.player, Actors.add(w, { kind = "player", name = "Ann" }) })
    sess:call("state", { modifiers = { shift = false } })
    Group.clear(w)
    reloaded(sess, function(fresh)
      A.same({ _G.IsInGroup(), fresh.state.group }, { false, "none" })
    end)
  end)
end

-- Another flavor opens a fresh sim world with no foe, so the old world's combat must not reach it through sess.state.
local function test_a_flavor_change_leaves_the_sim_combat_behind()
  H.withSession({ sim = {} }, function(sess)
    local w = sess.w
    local mob = Actors.add(w, { kind = "npc", name = "Brute", hostile = true, pos = { x = 0, y = 0 } })
    State.engage(w, mob, w.sim.player)
    local fresh, failure = Session.reload(sess, { flavor = w.flavor == "retail" and "tbc" or "retail" })
    A.eq(failure, nil, failure)
    local got = { _G.InCombatLockdown(), fresh.state.combat }
    fresh:shutdown()
    A.same(got, { false, false })
  end)
end

-- A group kind set only through a state request has no roster in the sim world; the reload keeps it.
local function test_a_group_set_by_a_state_request_survives_a_reload()
  H.withSession({ sim = {} }, function(sess)
    sess:call("state", { group = "party" })
    reloaded(sess, function(fresh)
      A.same({ _G.IsInGroup(), fresh.state.group }, { true, "party" })
    end)
  end)
end

-- Sim.restore straight on a world that a session state put in combat and in a party: the saved world had neither.
local function test_restore_turns_off_the_combat_and_group_the_saved_world_lacks()
  local state
  SimH.withSim("retail", {}, function(w)
    state = Sim.export(w)
  end)
  SimH.withSim("retail", { twoPhase = true }, function(w)
    w:setMock({ combat = true, group = "party" })
    local lockdown = {}
    Combat.listen(w, "lockdown", function(on)
      lockdown[#lockdown + 1] = on
    end)
    Sim.restore(w, state)
    A.same({ _G.InCombatLockdown(), _G.IsInGroup(), lockdown }, { false, false, { false } })
  end)
end

local function test_a_restore_that_raises_falls_back_to_a_fresh_sim_world()
  H.withSession({ sim = {} }, function(sess)
    sess.s:place(12, 3)
    local spec = {
      export = function()
        return {}
      end,
      restore = function()
        error("restore broke", 0)
      end,
    }
    Sim.persist(sess.w, "broken", spec)
    local restore = Sim.restore
    Sim.restore = function(w, simState)
      Sim.persist(w, "broken", spec)
      restore(w, simState)
    end
    local ok, fresh, failure = pcall(Session.reload, sess, nil)
    Sim.restore = restore
    A.eq(ok, true, fresh)
    A.truthy(fresh, failure)
    local pos = fresh.w.sim.player.pos
    fresh:shutdown()
    A.same({ failure, pos }, { "restore broke", SPAWN })
  end)
end

return function()
  test_a_combat_the_sim_dropped_stays_dropped_after_a_reload()
  test_a_group_the_sim_cleared_stays_cleared_after_a_reload()
  test_a_flavor_change_leaves_the_sim_combat_behind()
  test_a_group_set_by_a_state_request_survives_a_reload()
  test_restore_turns_off_the_combat_and_group_the_saved_world_lacks()
  test_a_restore_that_raises_falls_back_to_a_fresh_sim_world()
end
