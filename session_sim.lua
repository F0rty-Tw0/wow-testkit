-- Session sim: the viewer's and a script's handle on a sim world. step runs the sim clock, world reads the world
-- (sim_world.lua), reset puts the player back at the spawn and spawn adds a mob or a pack. Later slices add actions to
-- ACTIONS.
local M = {}

local SessionOptions = require("session_options")
local Sim = require("sim")
local SimMobs = require("sim_mobs")
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
  -- A pack of req.pack mobs (1 to SimMobs.RULES.maxPack) or one; the reply names the first.
  spawn = function(sess, req)
    local pack, max = req.pack, SimMobs.RULES.maxPack
    if pack ~= nil and (type(pack) ~= "number" or pack < 1 or pack > max or pack ~= math.floor(pack)) then
      fail("pack must be a whole number 1-%d", max)
    end
    local mobs
    if pack then
      mobs = sess.w:run(ENGINE, SimMobs.pack, sess.w, pack, req)
    else
      mobs = { sess.w:run(ENGINE, SimMobs.spawn, sess.w, req) }
    end
    local out = reply(sess)
    out.guid = mobs[1].guid

    return out, true
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

-- req = { action = "step", seconds } | { action = "world" } | { action = "reset", class? } | { action = "spawn", name?,
-- level?, health?, hostile?, pos?, loot?, ai?, pack? }. Replies { ok, world } and whether
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
-- open on the same flavor ("auto" included), else nil, so a toggled sim or another flavor opens a fresh world. A carried
-- world replaces opts.state with a copy holding its combat flag and group: the sim changes both after the last state
-- request, the reload applies opts.state before the sim world, and Sim.restore settles them against the export.
-- sess.state stays as the last state request left it, so a world that is not carried, or the fresh world a failed
-- reload falls back to, gets no combat that nothing on it would drop.
function M.carry(sess, opts)
  local w = sess.w
  local same = w.sim and opts.sim and w.flavor == SessionOptions.flavorOf(opts)
  if not same then
    sess.simState = nil
    return
  end
  local state = {}
  for key, value in pairs(opts.state) do
    state[key] = value
  end
  state.combat, state.group = w.mock.combat, w.mock.group
  opts.state, sess.simState = state, Sim.export(w)
end

-- Phase 2 of the install, after the bindings are in: what a login or a reload puts back on the sim world. prior is the
-- session this one follows, or nil. A restore that raises destroys the world first, so the reload's fallback can build
-- its own.
function M.restore(sess, prior)
  local w = sess.w
  if not w.sim then
    return
  end
  local ok, err = pcall(Sim.restore, w, prior and prior.simState)
  if not ok then
    w:destroy()
    error(err, 0)
  end
end

return M
