-- Scenario helpers for the sim world's combat units: s:clickUnit, s:clickGround, s:spawn and s:spawnPack. Each raises on a
-- world without the sim.
local M = {}

local SimMobs = require("sim_mobs")
local SimTarget = require("sim_target")

local ENGINE = "blizzard"
local LEFT = "LeftButton"

local function simWorld(s, method)
  if not s.w.sim then
    error(string.format("s:%s: needs Scenario.new{sim=...}", method), 3)
  end

  return s.w
end

function M.extend(Scenario)
  -- Clicks actor in the world with button (default LeftButton): a left click targets, a right click also attacks or
  -- loots (SimTarget.interact). Returns whether the world changed.
  function Scenario:clickUnit(actor, button)
    local w = simWorld(self, "clickUnit")

    return w:run(ENGINE, SimTarget.pointer, w, "click", { guid = actor.guid }, button or LEFT)
  end

  -- Clicks the ground at (x, y) with button (default LeftButton): a left click clears the target, or casts the ground
  -- spell in the targeting mode (SimGround). Returns whether the world changed.
  function Scenario:clickGround(x, y, button)
    local w = simWorld(self, "clickGround")

    return w:run(ENGINE, SimTarget.pointer, w, "click", { ground = { x = x, y = y } }, button or LEFT)
  end

  -- Adds a mob (SimMobs.spawn's opts) and returns its actor.
  function Scenario:spawn(opts)
    local w = simWorld(self, "spawn")

    return w:run(ENGINE, SimMobs.spawn, w, opts)
  end

  -- Adds n mobs in a row (SimMobs.pack) and returns their actors.
  function Scenario:spawnPack(n, opts)
    local w = simWorld(self, "spawnPack")

    return w:run(ENGINE, SimMobs.pack, w, n, opts)
  end
end

return M
