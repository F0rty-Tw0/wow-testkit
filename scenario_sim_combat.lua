-- Scenario helpers for the sim world's combat units: s:clickUnit and s:clickGround. Each raises on a world without the
-- sim.
local M = {}

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

  -- Left-clicks the ground at (x, y): the target clears.
  function Scenario:clickGround(x, y)
    local w = simWorld(self, "clickGround")

    return w:run(ENGINE, SimTarget.pointer, w, "click", { ground = { x = x, y = y } }, LEFT)
  end
end

return M
