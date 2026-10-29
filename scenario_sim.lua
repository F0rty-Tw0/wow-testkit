-- Scenario helpers for the sim world: s:move, s:face, s:place, s:key and s:simStep. Each raises on a world without the
-- sim.
local M = {}

local Keys = require("input_keys")
local Sim = require("sim")
local SimMove = require("sim_move")

local ENGINE = "blizzard"
local KEY_STATES = { down = Keys.down, up = Keys.up }

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

  -- Sends the key down or up (the client's key name, mods = { shift?, ctrl?, alt? } held while it runs); returns the reply
  -- of Keys.down or Keys.up. A key stays down until its up, across any number of simStep calls.
  function Scenario:key(key, state, mods)
    local w = simWorld(self, "key")
    local act = KEY_STATES[state]
    if not act then
      error(string.format('s:key: state must be "down" or "up", got %s', tostring(state)), 2)
    end

    return Keys.holding(w, mods, w.run, w, ENGINE, act, w, key, mods)
  end

  -- Runs seconds of the sim clock under the engine context; returns whether the world changed and the OnUpdate count.
  function Scenario:simStep(seconds)
    local w = simWorld(self, "simStep")

    return w:run(ENGINE, Sim.step, w, seconds)
  end
end

return M
