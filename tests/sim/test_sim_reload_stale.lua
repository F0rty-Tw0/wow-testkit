-- Sim reload over stale session state: a state request copies the world's combat flag and group into sess.state, and
-- the sim changes both later. The reload takes them from the world, and Sim.restore wins over them.
local A = require("assert")
local Actors = require("combat_actors")
local Combat = require("combat")
local Group = require("combat_group")
local H = require("tests.helpers.session")
local Session = require("session")
local Sim = require("sim")
local SimH = require("tests.helpers.sim")
local State = require("combat_state")

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

return function()
  test_a_combat_the_sim_dropped_stays_dropped_after_a_reload()
  test_a_group_the_sim_cleared_stays_cleared_after_a_reload()
  test_restore_turns_off_the_combat_and_group_the_saved_world_lacks()
end
