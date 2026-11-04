-- SimTarget: who the player targets and who the mouse is over. The pointer (a click or hover on a unit in the viewer)
-- and the key fakes (TargetUnit, ClearTarget, TargetNearestEnemy) all end in target and hover; interact is the
-- left and right click rule. Attack and loot are seams in w.sim.actions that later units fill.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local SimRange = require("sim_range")
local State = require("game.state")
local define = State.define

local MOUSEOVER = "mouseover"
local RIGHT = "RightButton"

-- source: assumed (spec 5.1) TargetNearestEnemy reaches 40 yards, measured after both reaches, in front of the player.
M.TAB_RANGE = 40

-- source: assumed (spec 8.1) a corpse is looted from 5 yards, measured after both reaches.
M.INTERACT_RANGE = 5

local function guidOf(actor)
  return actor and actor.guid or nil
end

-- Points the player at actor (nil clears). Returns whether the target changed; the event fires once per change.
function M.target(w, actor)
  local player = w.sim.player
  if player.targetGuid == guidOf(actor) then
    return false
  end
  Actors.setTarget(w, player, actor)

  return true
end

-- Puts the mouseover token on actor (nil clears). Returns whether it changed; UPDATE_MOUSEOVER_UNIT fires only then.
-- source: assumed (spec 5.1) the event fires on a change of the hovered unit, not on every pointer move over it.
function M.hover(w, actor)
  if Actors.get(w, MOUSEOVER) == actor then
    return false
  end
  if actor then
    Actors.bind(w, actor, MOUSEOVER)
  else
    Actors.unbind(w, MOUSEOVER)
  end
  Combat.fire(w, "UPDATE_MOUSEOVER_UNIT")

  return true
end

local function isCandidate(w, actor)
  local player = w.sim.player
  local reachable = SimRange.distance(player, actor) <= M.TAB_RANGE
  local inFront = SimRange.inFront(player, actor)
  local livingEnemy = actor.isEnemy and not actor.isDead

  return livingEnemy and inFront and reachable
end

-- Spawn order of every actor by guid, to break a tie in distance.
local function spawnRanks(w)
  local ranks = {}
  for index, guid in ipairs(w.combat.order) do
    ranks[guid] = index
  end

  return ranks
end

-- The live enemies in front of the player and within TAB_RANGE, nearest first, ties in spawn order.
-- source: assumed (spec 5.1) the nearest-first, spawn-order tie-break ordering of TargetNearestEnemy.
local function candidates(w)
  local ranks = spawnRanks(w)
  local player = w.sim.player
  local list = {}
  for _, guid in ipairs(w.combat.order) do
    local actor = w.combat.actors[guid]
    if isCandidate(w, actor) then
      list[#list + 1] = actor
    end
  end
  local function byDistanceThenSpawn(a, b)
    local da, db = SimRange.distance(player, a), SimRange.distance(player, b)
    if da == db then
      return ranks[a.guid] < ranks[b.guid]
    end

    return da < db
  end
  table.sort(list, byDistanceThenSpawn)

  return list
end

-- The candidate after the current target, wrapping; the nearest when the target is not one. nil without candidates.
-- source: assumed (spec 5.1) repeated presses walk the candidates in order and wrap after the last.
function M.nearestEnemy(w)
  local list = candidates(w)
  local current = w.sim.player.targetGuid
  for index, actor in ipairs(list) do
    if actor.guid == current then
      return list[index % #list + 1]
    end
  end

  return list[1]
end

-- Fires UI_ERROR_MESSAGE(errorType, message) for the global string name.
-- source: assumed (spec 5.1) the extract's UIErrorsFrame reads LE_GAME_ERR_* it never defines, so errorType is 0 unless a
-- scenario sets the constant.
function M.uiError(w, name)
  local suffix = name:gsub("^ERR_", "")
  local errorType = _G["LE_GAME_ERR_" .. suffix] or 0
  Combat.fire(w, "UI_ERROR_MESSAGE", errorType, _G[name])
end

local function loot(w, actor)
  local player = w.sim.player
  if SimRange.distance(player, actor) > M.INTERACT_RANGE then
    M.uiError(w, "ERR_LOOT_TOO_FAR")

    return
  end
  local act = w.sim.actions.loot
  if act then
    act(w, actor)
  end
end

local function attack(w, actor)
  local act = w.sim.actions.attack
  if act then
    act(w, actor)
  end
end

-- A click on actor. Left targets. Right targets, then a live enemy is attacked and a lootable corpse is looted (or the
-- too-far error); anything else stays a target. Returns whether the world was touched.
-- source: assumed (spec 5.1) the right-click table.
function M.interact(w, actor, button)
  local changed = M.target(w, actor)
  if button ~= RIGHT then
    return changed
  end
  if actor.isEnemy and not actor.isDead then
    attack(w, actor)

    return true
  end
  if actor.isDead and actor.lootable then
    loot(w, actor)

    return true
  end

  return changed
end

-- Offers the pointer to the handlers units hang on w.sim.seams.pointer (SimGround's targeting mode); the first one that
-- answers handled ends it. Returns handled, changed.
local function offered(w, kind, world, button)
  local seams = w.sim.seams
  for _, handler in ipairs(seams and seams.pointer or {}) do
    local handled, changed = handler(w, kind, world, button)
    if handled then
      return true, changed
    end
  end

  return false, false
end

-- The pointer on the world: "enter" hovers the unit world names (nil when none), "click" interacts with it; a left click
-- on the ground or an unknown guid clears the target. A click without world (a frame was hit) does nothing. A pointer
-- seam that handles the event ends it first. Returns whether the world changed.
function M.pointer(w, kind, world, button)
  local handled, taken = offered(w, kind, world, button)
  if handled then
    return taken
  end
  local guid = world and world.guid
  local actor = guid and w.combat.actors[guid]
  if kind == "enter" then
    return M.hover(w, actor)
  end
  if not world then
    return false
  end
  if actor then
    return M.interact(w, actor, button)
  end
  local pressed = button or "LeftButton"
  -- source: assumed (spec 5.1) a left click on the ground or an unknown guid clears the target; other buttons do nothing.
  if pressed == "LeftButton" then
    return M.target(w, nil)
  end

  return false
end

-- Defines TargetUnit, ClearTarget and TargetNearestEnemy, and the actions table the later units fill.
function M.install(w)
  w.sim.actions = {}
  define(w, "TargetUnit", function(unit)
    local actor = Actors.get(w, unit)
    if actor then
      M.target(w, actor)
    end
  end)
  define(w, "ClearTarget", function()
    M.target(w, nil)
  end)
  define(w, "TargetNearestEnemy", function()
    local actor = M.nearestEnemy(w)
    if actor then
      M.target(w, actor)
    end
  end)
end

return M
