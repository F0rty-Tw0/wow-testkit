-- Sim: the opt-in simulated world. Sim.install (phase 1) puts the player, its class and level, the world bounds and the
-- map in a Scenario world (Scenario.new { sim = true | { class?, level? } }); later units hang their frame and reset
-- steps on w.sim.hooks, so this unit never names them.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local SimKeys = require("sim_keys")
local SimMove = require("sim_move")
local SimRange = require("sim_range")
local SimUpdate = require("sim_update")

local DEFAULT_CLASS = "WARRIOR"
local DEFAULT_LEVEL = 10
local MAX_LEVEL = 100
local PLAYER = "player"
local FRAME = 1 / 60

-- The units that hang their state, fakes and frame steps on a new sim world, in this order.
local UNITS = { SimMove, SimRange }

-- source: assumed the kit's one map: the whole sim world is this uiMapID.
M.MAP_ID = 1

-- The player's place on login: facing 0 is north (+y).
M.SPAWN = { x = 0, y = -10, facing = 0 }

-- source: assumed the kit's two classes: a Warrior starts at 0 of 100 rage, a Mage at 100 of 100 mana.
-- grug: minimal kit, Task 5.6 moves it to sim_classes.lua
M.CLASSES = {
  WARRIOR = { className = "Warrior", powerToken = "RAGE", powerMax = 100, power = 0 },
  MAGE = { className = "Mage", powerToken = "MANA", powerMax = 100, power = 100 },
}

-- source: assumed the world is a 100 x 100 square centred on the origin, and the map shows it whole: map x =
-- (pos.x - left) / size, map y = (top - pos.y) / size.
local BOUNDS = { minX = -50, maxX = 50, minY = -50, maxY = 50 }
local MAP_RECT = { left = -50, top = 50, size = 100 }

-- Combat kinds that mean "the world changed"; each bumps w.sim.activity.
local ACTIVITY_KINDS = {
  "moved",
  "health",
  "healthmax",
  "power",
  "aura",
  "cast",
  "target",
  "flags",
  "lockdown",
  "death",
  "spawn",
  "despawn",
}

local function wholeLevel(level)
  return type(level) == "number" and level >= 1 and level <= MAX_LEVEL and level == math.floor(level)
end

-- Validates sim (nil, true or {} = defaults; { class?, level?, twoPhase? }) and returns { class, level, twoPhase? }.
-- twoPhase is set only by the session's install: it tells Scenario.new to skip phase 2.
function M.options(sim)
  local given = type(sim) == "table" and sim or {}
  local class = given.class or DEFAULT_CLASS
  local level = given.level or DEFAULT_LEVEL
  if not M.CLASSES[class] then
    error("sim: class must be WARRIOR or MAGE", 2)
  end
  if not wholeLevel(level) then
    error("sim: level must be a whole number 1-100", 2)
  end
  return { class = class, level = level, twoPhase = given.twoPhase }
end

-- Makes actor a player of class: name, power bar and power; the level is the caller's.
function M.applyClass(_w, actor, class)
  local row = M.CLASSES[class]
  actor.className = row.className
  actor.classFile = class
  actor.powerToken = row.powerToken
  actor.powerType = Actors.powerNumber(row.powerToken)
  actor.powerMax = row.powerMax
  actor.power = row.power
end

local function bumpActivity(w)
  w.sim.activity = w.sim.activity + 1
end

local function countActivity(w)
  for _, kind in ipairs(ACTIVITY_KINDS) do
    Combat.listen(w, kind, function()
      bumpActivity(w)
    end)
  end
end

-- Phase 1: installs combat, takes the player actor and builds w.sim. Raises when the world already has a sim.
function M.install(w, sim)
  local o = M.options(sim)
  if w.sim then
    error("Sim.install: already installed", 2)
  end
  Combat.install(w)
  local player = Actors.get(w, PLAYER)
  M.applyClass(w, player, o.class)
  player.level = o.level
  player.pos = { x = M.SPAWN.x, y = M.SPAWN.y }
  player.facing = M.SPAWN.facing
  w.sim = {
    player = player,
    class = o.class,
    level = o.level,
    bounds = { minX = BOUNDS.minX, maxX = BOUNDS.maxX, minY = BOUNDS.minY, maxY = BOUNDS.maxY },
    mapRect = { left = MAP_RECT.left, top = MAP_RECT.top, size = MAP_RECT.size },
    intents = {},
    clock = { t0 = w.now, carry = 0 },
    activity = 0,
    hooks = { frame = {}, reset = {} },
  }
  countActivity(w)
  for _, unit in ipairs(UNITS) do
    unit.install(w)
  end
  w:setMock({ zone = { mapID = M.MAP_ID } })
  SimRange.syncMap(w)
  return w.sim
end

-- Phase 2: what a login or a hot reload puts back on a world that phase 1 built: the fallback key commands and default
-- keys. simState (the saved sim of a hot reload) is Task 1.6's; nil is a fresh world.
function M.restore(w, _simState)
  SimKeys.install(w)
end

-- Runs seconds of the sim clock: whole 1/60 s frames (the remainder carries to the next step), each running the frame
-- hooks and then the world clock; then the player's map place follows the walk, and one OnUpdate pass runs with the
-- whole step as elapsed. Returns whether the world changed and how many OnUpdate scripts ran.
function M.step(w, seconds)
  if type(seconds) ~= "number" or not (seconds >= 0 and seconds < math.huge) then
    error("Sim.step: seconds must be a finite non-negative number, got " .. tostring(seconds), 2)
  end
  local clock = w.sim.clock
  local before = w.sim.activity
  local acc = clock.carry + seconds
  local frames = math.floor(acc * 60 + 1e-9)
  clock.carry = acc - frames * FRAME
  for _ = 1, frames do
    for _, fn in ipairs(w.sim.hooks.frame) do
      fn(w, FRAME)
    end
    w:advance(FRAME)
  end
  SimRange.syncMap(w)
  local updates = SimUpdate.run(w, seconds)

  return w.sim.activity ~= before or updates > 0, updates
end

return M
