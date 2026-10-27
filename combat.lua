-- Combat world: Combat.install(w) adds the actors and auras on top of a Scenario world's unit fixtures and game-state
-- fakes, and owns the hooks the later combat modules share. State changes call Combat.emit(w, kind, ...); modules
-- Combat.listen to the kinds they react to (cvar, health, healthmax, power, aura, cast, target, flags, death, spawn,
-- despawn, moved, threat). Without Combat.install nothing here is active.
local M = {}

local unpack = unpack

local ENGINE = "blizzard"

-- Registers fn(...) for kind; listeners run in registration order.
function M.listen(w, kind, fn)
  local listeners = w.combat.listeners
  listeners[kind] = listeners[kind] or {}
  table.insert(listeners[kind], fn)
end

-- Calls every listener of kind with ...; a listener that raises is recorded as a world error and the rest still run.
function M.emit(w, kind, ...)
  local list = w.combat.listeners[kind]
  if not list then
    return
  end
  local args, n = { ... }, select("#", ...)
  for i = 1, #list do
    local fn = list[i]
    xpcall(function()
      return fn(unpack(args, 1, n))
    end, function(err)
      w:recordError(err, debug.traceback())
    end)
  end
end

-- Runs fn once after seconds of world-clock time, under the engine ("blizzard") context. Returns the timer handle.
function M.later(w, seconds, fn)
  return w:schedule(seconds, function()
    w:run(ENGINE, fn)
  end, 1)
end

-- Returns w.combat, creating it on the first call. Needs the units and game-state fakes Scenario.new installs.
function M.install(w)
  if w.combat then
    return w.combat
  end
  if not (w.unitState and w.mock) then
    error("Combat.install: needs a Scenario world (Units.install + Game.install)", 2)
  end
  local c = { actors = {}, order = {}, spells = w.mock.spells, listeners = {}, seq = 0, t0 = w.now }
  w.combat = c
  -- Required here, not at the top: the modules require this one for emit and listen.
  require("combat_actors").install(w)
  require("combat_auras").install(w)
  return c
end

return M
