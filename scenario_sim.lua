-- Scenario helpers for the sim world: s:move, s:face, s:place and s:simStep. Each raises on a world without the sim.
local M = {}

local Sim = require("sim")
local SimMove = require("sim_move")

local ENGINE = "blizzard"

local function simWorld(s, method)
  if not s.w.sim then
    error(string.format("s:%s needs Scenario.new { sim = true }", method), 3)
  end

  return s.w
end

function M.extend(Scenario)
  -- Replaces the walk intents with the names spec holds true (forward, backward, turnLeft, turnRight, strafeLeft,
  -- strafeRight, autorun, walk); {} stops.
  function Scenario:move(spec)
    SimMove.set(simWorld(self, "move"), spec)
  end

  -- Turns the player to radians (0 is north, counter-clockwise).
  function Scenario:face(radians)
    SimMove.setFacing(simWorld(self, "face"), radians)
  end

  -- Puts the player at (x, y), clamped to the world bounds.
  function Scenario:place(x, y)
    SimMove.place(simWorld(self, "place"), x, y)
  end

  -- Runs seconds of the sim clock under the engine context; returns whether the world changed and the OnUpdate count.
  function Scenario:simStep(seconds)
    local w = simWorld(self, "simStep")

    return w:run(ENGINE, Sim.step, w, seconds)
  end
end

return M
