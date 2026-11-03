-- Sim combat test helper: a sim world, a foe, an event record and the session reload idiom that tasks of phase 3 share.
-- Tests never read a client extract or install.
local Actors = require("combat_actors")
local Log = require("combat_log")
local Session = require("session")
local SimHelper = require("tests.helpers.sim")

local M = {}

M.FLAVORS = SimHelper.FLAVORS

-- Runs fn(w, s, player) on a fresh sim world (simOpts defaults to {}); the world is always destroyed.
function M.withSim(flavor, fn, simOpts)
  SimHelper.withSim(flavor, simOpts, function(w, s)
    fn(w, s, w.sim.player)
  end)
end

-- A hostile npc "Foe" (100/100) at (x, y) facing south; extra's fields replace the defaults ({ hostile = false } makes a
-- friend).
function M.foe(w, x, y, extra)
  local given = extra or {}
  local actor = Actors.add(w, {
    kind = "npc",
    name = "Foe",
    hostile = given.hostile ~= false,
    health = 100,
    healthMax = 100,
    pos = { x = x, y = y },
  })
  actor.facing = math.pi
  for key, value in pairs(given) do
    if key ~= "hostile" then
      actor[key] = value
    end
  end

  return actor
end

-- A frame registered for events; log[i] = { event, n, ... } in firing order (payload from index 3), also keyed .event,
-- .now (the world clock) and .ts (the combat log timestamp).
function M.record(w, events)
  local log = {}
  local frame = _G.CreateFrame("Frame")
  for _, event in ipairs(events) do
    frame:RegisterEvent(event)
  end
  frame:SetScript("OnEvent", function(_, event, ...)
    local entry = { event, select("#", ...), ... }
    entry.event, entry.now, entry.ts = event, w.now, Log.timestamp(w)
    log[#log + 1] = entry
  end)

  return log
end

-- Reloads sess (Session.reload with over), runs fn(fresh) and always shuts the fresh session down.
function M.reloaded(sess, fn, over)
  local fresh, failure = Session.reload(sess, over)
  if not fresh then
    error(failure, 0)
  end
  local ok, err = pcall(fn, fresh)
  fresh:shutdown()
  if not ok then
    error(err, 0)
  end
end

return M
