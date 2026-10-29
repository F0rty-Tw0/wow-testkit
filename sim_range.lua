-- SimRange: where things are for the APIs that ask. One rule gives every answer: the distance between two actors is
-- the gap between their places less both reaches. The fakes (UnitPosition, UnitInRange, CheckInteractDistance, the
-- spell and item range checks) read it, and syncMap keeps the player's map position in step with the walk.
local M = {}

local Actors = require("combat_actors")
local State = require("game.state")
local define = State.define

local PLAYER, TARGET = "player", "target"

-- source: assumed (spec 3.3) every actor reaches 1.5 yards from its centre; actor.reach overrides it.
M.REACH = 1.5

-- source: assumed (spec 4.3) UnitInRange reaches 40 yards.
local GROUP_RANGE = 40

-- source: assumed (spec 4.3) CheckInteractDistance's index -> yards: 1 inspect, 2 trade, 3 duel, 4 follow.
local INTERACT = { [1] = 28, [2] = 11.11, [3] = 9.9, [4] = 28 }

local function reach(actor)
  return actor.reach or M.REACH
end

-- Yards between a and b after both reaches, never below 0.
function M.distance(a, b)
  local dx, dy = b.pos.x - a.pos.x, b.pos.y - a.pos.y
  local gap = math.sqrt(dx * dx + dy * dy) - reach(a) - reach(b)

  return math.max(0, gap)
end

-- source: confirmed (HereBeDragons) UnitPosition's first return is the north coordinate and its second is west of the
-- map's east edge. Kit +x is east and +y north, so wowX = pos.y and wowY = -pos.x.
function M.toWow(pos)
  return pos.y, -pos.x
end

-- Map coordinates (0..1) of a world place: the map shows the whole world rect, north up.
function M.toMap(w, pos)
  local rect = w.sim.mapRect

  return (pos.x - rect.left) / rect.size, (rect.top - pos.y) / rect.size
end

-- Whether b is in the half plane a faces: facing 0 looks north and turns counter-clockwise; a coincident b counts.
function M.inFront(a, b)
  local facing = a.facing or 0
  local dx, dy = b.pos.x - a.pos.x, b.pos.y - a.pos.y

  return -math.sin(facing) * dx + math.cos(facing) * dy >= 0
end

-- Writes the player's map place to w.mock.zone.position.
function M.syncMap(w)
  local x, y = M.toMap(w, w.sim.player.pos)
  w.mock.zone.position = { x = x, y = y }
end

local function inGroup(w, actor)
  return actor == Actors.get(w, PLAYER) or actor.inParty or actor.inRaid
end

-- The actor a token names when it is the player or a group member, else nil.
local function groupActor(w, unit)
  local actor = Actors.get(w, unit)
  if actor and inGroup(w, actor) then
    return actor
  end
end

local function unitPosition(w, unit)
  local actor = groupActor(w, unit)
  if not actor then
    return
  end
  local x, y = M.toWow(actor.pos)

  return x, y, 0, w.mock.zone.mapID
end

local function unitInRange(w, unit)
  local actor = groupActor(w, unit)
  if not actor then
    return false, false
  end

  return M.distance(Actors.get(w, PLAYER), actor) <= GROUP_RANGE, true
end

local function interactDistance(w, unit, index)
  local actor = Actors.get(w, unit)
  local limit = INTERACT[index]
  if not (actor and limit) then
    return false
  end

  return M.distance(Actors.get(w, PLAYER), actor) <= limit
end

-- Whether unit (default target) is within minRange..maxRange of the player; nil when the record has no maxRange or no
-- such unit stands there.
local function inRangeOf(w, record, unit)
  local maxRange = record and record.maxRange
  local actor = Actors.get(w, unit or TARGET)
  if not (maxRange and actor) then
    return nil
  end
  local yards = M.distance(Actors.get(w, PLAYER), actor)

  return yards >= (record.minRange or 0) and yards <= maxRange
end

local function spellInRange(w, spell, unit)
  local _, record = State.findRecord(w.mock.spells, spell)

  return inRangeOf(w, record, unit)
end

local function itemInRange(w, item, unit)
  local _, record = State.findRecord(w.mock.items, item)

  return inRangeOf(w, record, unit)
end

local function oneOrZero(flag)
  if flag == nil then
    return nil
  end

  return flag and 1 or 0
end

-- Defines the range fakes; each exists only where the flavor lists the name. UnitInRange replaces the fixture reader.
function M.install(w)
  define(w, "UnitPosition", function(unit)
    return unitPosition(w, unit)
  end)
  define(w, "UnitInRange", function(unit)
    return unitInRange(w, unit)
  end)
  define(w, "CheckInteractDistance", function(unit, index)
    return interactDistance(w, unit, index)
  end)
  define(w, "C_Spell.IsSpellInRange", function(spell, unit)
    return spellInRange(w, spell, unit)
  end)
  define(w, "IsSpellInRange", function(spell, unit)
    return oneOrZero(spellInRange(w, spell, unit))
  end)
  define(w, "C_Item.IsItemInRange", function(item, unit)
    return itemInRange(w, item, unit)
  end)
end

return M
