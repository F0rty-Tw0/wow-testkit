-- Scenario combat steps: s:pull(target) engages an enemy and starts the AI, s:combat(entries) runs a timeline on the world
-- clock and s:kill(token) kills a unit. Each installs the combat world first and runs under the engine ("blizzard") context.
-- A unit that does not exist raises at the call, naming the step.
local M = {}

local Actors = require("combat_actors")
local Ai = require("combat_ai")
local Combat = require("combat")
local Resolve = require("combat_resolve")
local Timeline = require("combat_timeline")

local ENGINE = "blizzard"

-- The actor a token names, or the actor itself; raises naming the step. Level 3 puts the position at the scenario's call.
local function unitOf(w, token, step)
  local actor = type(token) == "table" and token or Actors.get(w, token)
  if not actor then
    error(string.format("%s: no unit '%s'; add it with Actors.add first", step, tostring(token)), 3)
  end
  return actor
end

function M.extend(Scenario)
  -- target: a unit token, or an Actors.add spec for a new enemy (hostile, kind "npc" unless given; spec.ai becomes its
  -- behaviour rules). Engages the enemy with the player and the group and starts the AI of every actor that has rules.
  function Scenario:pull(target)
    local w = self.w
    Combat.install(w)
    local enemy
    if type(target) == "table" and not target.guid then
      local spec = { kind = "npc", hostile = true }
      for key, value in pairs(target) do
        spec[key] = value
      end
      enemy = w:run(ENGINE, Actors.add, w, spec)
      enemy.ai = target.ai
    else
      enemy = unitOf(w, target, "s:pull")
    end
    if not enemy.isEnemy then
      error("s:pull: '" .. tostring(enemy.name) .. "' is not hostile", 2)
    end
    w:run(ENGINE, Ai.pull, w, enemy)
  end

  -- entries: see combat_timeline.lua. Each runs that many seconds from now, as s:advance moves the clock.
  function Scenario:combat(entries)
    local w = self.w
    Combat.install(w)
    w:run(ENGINE, Timeline.run, w, entries, "s:combat")
  end

  function Scenario:kill(token)
    local w = self.w
    Combat.install(w)
    local actor = unitOf(w, token, "s:kill")
    w:run(ENGINE, Resolve.kill, w, actor)
  end
end

return M
