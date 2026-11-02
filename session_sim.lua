-- Session sim: the viewer's and a script's handle on a sim world. step runs the sim clock, world reads the world
-- (sim_world.lua) and reset puts the player back at the spawn. Later slices add actions to ACTIONS.
local M = {}

local SessionOptions = require("session_options")
local Sim = require("sim")
local SimWorld = require("sim_world")

local ENGINE = "blizzard"
-- A longer step would hide the walk between its frames from the viewer, which posts a step every 100 ms.
local MAX_STEP = 0.25

local function fail(fmt, ...)
  error("sim: " .. string.format(fmt, ...), 0)
end

local function reply(sess)
  return { ok = true, world = SimWorld.build(sess.w) }
end

-- Each action returns its reply and whether it changed the world.
local ACTIONS = {
  -- Session:call runs methods with no world context, so the step goes through s:simStep, which runs it as the engine.
  step = function(sess, req)
    local seconds = req.seconds
    if type(seconds) ~= "number" or not (seconds > 0 and seconds <= MAX_STEP) then
      fail("seconds must be a number above 0 and at most %s", MAX_STEP)
    end
    local changed = sess.s:simStep(seconds)

    return reply(sess), changed
  end,
  world = function(sess)
    return reply(sess), false
  end,
  reset = function(sess, req)
    sess.w:run(ENGINE, Sim.reset, sess.w, req.class)

    return reply(sess), true
  end,
}
M.ACTIONS = ACTIONS

local function validList()
  local names = {}
  for name in pairs(ACTIONS) do
    names[#names + 1] = name
  end
  table.sort(names)

  return table.concat(names, ", ")
end

-- req = { action = "step", seconds } | { action = "world" } | { action = "reset", class? }. Replies { ok, world } and whether
-- the world changed. A bad request raises "sim: ...", which Session:call answers as { ok = false, error }.
function M.call(sess, req)
  if not sess.w.sim then
    fail("this session was opened without the sim (start it with --sim)")
  end
  local run = ACTIONS[req.action]
  if not run then
    fail("unknown action '%s'; valid: %s", tostring(req.action), validList())
  end

  return run(sess, req)
end

-- The Scenario.new sim option for a session opened with opts: opts.sim (true or { class?, level? }) as a two-phase install,
-- or nil for a session without the sim. Raises on a class or level the sim refuses.
function M.install(opts)
  if not opts.sim then
    return nil
  end
  local o = Sim.options(opts.sim)

  return { class = o.class, level = o.level, twoPhase = true }
end

-- Keeps sess's sim world for the session a reload opens with opts: sess.simState is its export when both have the sim and
-- open on the same flavor ("auto" included), else nil, so a toggled sim or another flavor opens a fresh world. A sim
-- world first writes its combat flag and group into sess.state: the sim changes both after the last state request, and
-- the reload applies sess.state before the sim world.
function M.carry(sess, opts)
  local w = sess.w
  if w.sim then
    sess.state.combat, sess.state.group = w.mock.combat, w.mock.group
  end
  local same = w.sim and opts.sim and w.flavor == SessionOptions.flavorOf(opts)
  sess.simState = same and Sim.export(w) or nil
end

-- Phase 2 of the install, after the bindings are in: what a login or a reload puts back on the sim world. prior is the
-- session this one follows, or nil.
function M.restore(sess, prior)
  if sess.w.sim then
    Sim.restore(sess.w, prior and prior.simState)
  end
end

return M
