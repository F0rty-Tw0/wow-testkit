-- SimMove: the player's walk. Intents (forward, turnLeft, ...) are plain flags in w.sim.intents; SimMove.frame integrates
-- them one frame at a time, writes the position through Actors.setPos and fires PLAYER_STARTED_MOVING and
-- PLAYER_STOPPED_MOVING on transitions. The key fakes (MoveForwardStart, ToggleAutoRun, ...) only set intents.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local State = require("game.state")

local TAU = 2 * math.pi

-- source: assumed (spec 3.3) the speeds in yards per second: run 7, walk 2.5, backpedal 4.5, swim 4.722222 (the client's
-- swim speed), flight 7.
M.SPEEDS = { run = 7, walk = 2.5, back = 4.5, swim = 4.722222, flight = 7 }
-- source: assumed (spec 3.3) a full turn takes two seconds.
M.TURN = math.pi

local INTENTS = { "forward", "backward", "turnLeft", "turnRight", "strafeLeft", "strafeRight", "autorun", "walk" }
local VALID = {}
for _, name in ipairs(INTENTS) do
  VALID[name] = true
end
local VALID_LIST = table.concat(INTENTS, ", ")

-- A key press that moves along the facing takes the character off autorun.
local CANCELS_AUTORUN = { forward = true, backward = true }

-- Fake name -> { intent, on } for the key calls that only set one.
local KEYS = {
  MoveForwardStart = { "forward", true },
  MoveForwardStop = { "forward", false },
  MoveBackwardStart = { "backward", true },
  MoveBackwardStop = { "backward", false },
  TurnLeftStart = { "turnLeft", true },
  TurnLeftStop = { "turnLeft", false },
  TurnRightStart = { "turnRight", true },
  TurnRightStop = { "turnRight", false },
  StrafeLeftStart = { "strafeLeft", true },
  StrafeLeftStop = { "strafeLeft", false },
  StrafeRightStart = { "strafeRight", true },
  StrafeRightStop = { "strafeRight", false },
}

-- 1 when only positive holds, -1 when only negative holds, else 0.
local function sign(positive, negative)
  return (positive and 1 or 0) - (negative and 1 or 0)
end

local function bumpActivity(w)
  w.sim.activity = w.sim.activity + 1
end

-- Sets or clears one intent; raises on a name outside INTENTS.
function M.intent(w, name, on)
  if not VALID[name] then
    error(string.format("SimMove.intent: unknown intent '%s'; valid: %s", tostring(name), VALID_LIST), 2)
  end
  local intents = w.sim.intents
  intents[name] = on and true or nil
  if on and CANCELS_AUTORUN[name] then
    intents.autorun = nil
  end
end

-- Replaces the intent set with the names spec holds true; {} stops. Walk is a pace, not a motion: it stays as ToggleRun
-- left it unless spec names it.
function M.set(w, spec)
  local walk = w.sim.intents.walk
  for _, name in ipairs(INTENTS) do
    w.sim.intents[name] = nil
  end
  if spec.walk == nil then
    w.sim.intents.walk = walk
  end
  for _, name in ipairs(INTENTS) do
    if spec[name] then
      M.intent(w, name, true)
    end
  end
  for name in pairs(spec) do
    if not VALID[name] then
      M.intent(w, name, true)
    end
  end
end

-- Sets the facing (radians, wrapped to [0, 2pi)); a change counts as world activity.
function M.setFacing(w, radians)
  local player = w.sim.player
  local facing = radians % TAU
  if facing ~= player.facing then
    player.facing = facing
    bumpActivity(w)
  end
end

-- Puts the player at (x, y), clamped to the world bounds.
function M.place(w, x, y)
  local b = w.sim.bounds
  Actors.setPos(w, w.sim.player, math.max(b.minX, math.min(x, b.maxX)), math.max(b.minY, math.min(y, b.maxY)))
end

-- The speed of the current intents: 0 when still.
local function speedOf(intents, along, across)
  if along == 0 and across == 0 then
    return 0
  elseif along < 0 and across == 0 then
    return M.SPEEDS.back
  end

  return intents.walk and M.SPEEDS.walk or M.SPEEDS.run
end

-- The unit step direction for facing: forward (-sin f, cos f), right (cos f, sin f), normalized.
local function direction(facing, along, across)
  local dx = -math.sin(facing) * along + math.cos(facing) * across
  local dy = math.cos(facing) * along + math.sin(facing) * across
  local length = math.sqrt(dx * dx + dy * dy)

  return dx / length, dy / length
end

local function setMoving(w, moving)
  local sim = w.sim
  if sim.moving == moving then
    return
  end
  sim.moving = moving
  Combat.fire(w, moving and "PLAYER_STARTED_MOVING" or "PLAYER_STOPPED_MOVING")
end

-- One frame of dt seconds: turn, then walk.
function M.frame(w, dt)
  local sim = w.sim
  local intents = sim.intents
  local turn = sign(intents.turnLeft, intents.turnRight)
  if turn ~= 0 then
    M.setFacing(w, sim.player.facing + turn * M.TURN * dt)
  end
  local along = sign(intents.forward or intents.autorun, intents.backward)
  local across = sign(intents.strafeRight, intents.strafeLeft)
  local speed = speedOf(intents, along, across)
  sim.speed = speed
  if speed > 0 then
    local dx, dy = direction(sim.player.facing, along, across)
    local pos = sim.player.pos
    M.place(w, pos.x + dx * speed * dt, pos.y + dy * speed * dt)
  end
  setMoving(w, speed > 0)
end

local function isPlayer(w, unit)
  return type(unit) == "string" and Actors.get(w, unit:lower()) == w.sim.player
end

local function defineKeys(w)
  for name, key in pairs(KEYS) do
    State.define(w, name, function()
      M.intent(w, key[1], key[2])
    end, State.ALL)
  end
  State.define(w, "ToggleAutoRun", function()
    M.intent(w, "autorun", not w.sim.intents.autorun)
  end, State.ALL)
  State.define(w, "ToggleRun", function()
    M.intent(w, "walk", not w.sim.intents.walk)
  end, State.ALL)
end

local function defineReaders(w)
  State.define(w, "GetUnitSpeed", function(unit)
    local current = isPlayer(w, unit) and w.sim.speed or 0

    return current, M.SPEEDS.run, M.SPEEDS.flight, M.SPEEDS.swim
  end, State.ALL)
  State.define(w, "IsPlayerMoving", function()
    return w.sim.moving
  end, State.ALL)
  State.define(w, "GetPlayerFacing", function()
    return w.sim.player.facing
  end, State.ALL)
end

-- Stops the walk: no intent (walk included), speed 0, and PLAYER_STOPPED_MOVING when the player was moving.
function M.stop(w)
  w.sim.intents = {}
  w.sim.speed = 0
  setMoving(w, false)
end

-- Adds the walk state to w.sim, hangs the frame step on the frame hooks and the stop on the reset hooks, and defines the
-- key fakes.
function M.install(w)
  w.sim.moving = false
  w.sim.speed = 0
  table.insert(w.sim.hooks.frame, M.frame)
  table.insert(w.sim.hooks.reset, M.stop)
  defineKeys(w)
  defineReaders(w)
end

return M
