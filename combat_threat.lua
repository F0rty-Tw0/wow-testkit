-- Threat: an enemy actor keeps the list of actors it has threat against (enemy.threatList = { order, value }, insertion
-- order and threat by GUID). Each change rewrites the source actors' fixture fields threatOn[enemy.guid] (the status
-- against that enemy) and threat (the highest status over all enemies), which UnitThreatSituation reads, fires
-- UNIT_THREAT_LIST_UPDATE for the enemy and UNIT_THREAT_SITUATION_UPDATE for each source whose status changed, and emits
-- the "threat" hook. Installs UnitDetailedThreatSituation. Every threat number is the caller's data.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

local unpack = unpack

local function check(w, actor, name)
  if type(actor) ~= "table" or w.combat.actors[actor.guid] ~= actor then
    error("Threat." .. name .. ": not an actor of this world", 3)
  end
end

function M.get(enemy, source)
  local list = enemy.threatList
  return list and list.value[source.guid] or 0
end

-- The source with the most threat on enemy's list (the first on the list among equals), or nil.
function M.top(enemy)
  local list = enemy.threatList
  local top
  for _, source in ipairs(list and list.order or {}) do
    if not top or list.value[source.guid] > list.value[top.guid] then
      top = source
    end
  end
  return top
end

-- The enemy's target, when the target is on its list.
local function primaryOf(w, enemy)
  local target = enemy.targetGuid and w.combat.actors[enemy.targetGuid]
  return target and enemy.threatList.value[target.guid] and target or nil
end

-- Returns isTanking, status, scaledPercentage, rawPercentage, rawThreat for a source on the enemy's list, nothing for a
-- source off it. Percentages are against the primary target's threat (the top threat when the enemy has none).
-- source: confirmed (row C12) status 0 below 100% and not primary, 1 above 100% but not primary, 2 primary while another
-- is above 100%, 3 primary with nobody above; assumed the percentage base and rawPercentage equal to scaledPercentage.
function M.situation(w, enemy, source)
  local list = enemy.threatList
  local value = list and list.value[source.guid]
  if not value then
    return
  end
  local primary = primaryOf(w, enemy)
  local top = M.top(enemy)
  local base = list.value[(primary or top).guid]
  local tanking = primary == source
  local status
  if tanking then
    status = list.value[top.guid] > base and 2 or 3
  else
    status = value > base and 1 or 0
  end
  local percent = base > 0 and value / base * 100 or 0
  return tanking, status, percent, percent, value
end

local function highest(actor)
  local best
  for _, status in pairs(actor.threatOn or {}) do
    if best == nil or status > best then
      best = status
    end
  end
  return best
end

-- Rewrites the statuses of everything on the enemy's list and of the sources just taken off it; returns the actors whose
-- highest status changed.
local function refresh(w, enemy, removed)
  local affected = {}
  for _, source in ipairs(enemy.threatList and enemy.threatList.order or {}) do
    local _, status = M.situation(w, enemy, source)
    source.threatOn = source.threatOn or {}
    source.threatOn[enemy.guid] = status
    affected[#affected + 1] = source
  end
  for _, source in ipairs(removed or {}) do
    source.threatOn[enemy.guid] = nil
    affected[#affected + 1] = source
  end
  local changed = {}
  for _, source in ipairs(affected) do
    local status = highest(source)
    if status ~= source.threat then
      source.threat = status
      changed[#changed + 1] = source
    end
  end
  return changed
end

-- source: assumed (row C12) both events carry the unit token of the actor they are about: the enemy for the list, the
-- source for the situation; one event per token naming the actor, as the unit events do.
local function fanOut(w, actor, event)
  for _, token in ipairs(Actors.tokens(w, actor)) do
    Combat.fire(w, event, token)
  end
end

local function announce(w, enemy, listChanged, changed)
  if listChanged then
    fanOut(w, enemy, "UNIT_THREAT_LIST_UPDATE")
  end
  for _, source in ipairs(changed) do
    fanOut(w, source, "UNIT_THREAT_SITUATION_UPDATE")
  end
  if listChanged or #changed > 0 then
    Combat.emit(w, "threat", enemy)
  end
end

-- Adds amount (negative lowers, the total stays at 0 or more) to source's threat on enemy; a source joins the list on its
-- first add, even at 0.
function M.add(w, enemy, source, amount)
  check(w, enemy, "add")
  check(w, source, "add")
  if type(amount) ~= "number" then
    error("Threat.add: amount must be a number, got " .. type(amount), 2)
  end
  local list = enemy.threatList or { order = {}, value = {} }
  enemy.threatList = list
  local old = list.value[source.guid]
  local new = math.max(0, (old or 0) + amount)
  if old == nil then
    list.order[#list.order + 1] = source
  end
  list.value[source.guid] = new
  announce(w, enemy, new ~= old, refresh(w, enemy))
end

function M.clear(w, enemy)
  check(w, enemy, "clear")
  local list = enemy.threatList
  if not list or #list.order == 0 then
    return
  end
  enemy.threatList = nil
  announce(w, enemy, true, refresh(w, enemy, list.order))
end

local function drop(w, enemy, source)
  local list = enemy.threatList
  list.value[source.guid] = nil
  for i, listed in ipairs(list.order) do
    if listed == source then
      table.remove(list.order, i)
      break
    end
  end
  announce(w, enemy, true, refresh(w, enemy, { source }))
end

function M.install(w)
  -- An enemy's target decides who is primary: statuses change with it, the list does not.
  Combat.listen(w, "target", function(actor)
    if actor.threatList then
      announce(w, actor, false, refresh(w, actor))
    end
  end)
  -- A despawned actor leaves every list, and its own list goes with it.
  Combat.listen(w, "despawn", function(actor)
    for _, guid in ipairs({ unpack(w.combat.order) }) do
      local enemy = w.combat.actors[guid]
      if enemy.threatList and enemy.threatList.value[actor.guid] then
        drop(w, enemy, actor)
      end
    end
    M.clear(w, actor)
  end)
  -- source: confirmed (row C12) the five returns; assumed (row C12) nothing is returned for a source off the list, as for
  -- UnitThreatSituation's nil.
  define(w, "UnitDetailedThreatSituation", function(unit, mob)
    local source, enemy = Actors.get(w, unit), Actors.get(w, mob)
    if not (source and enemy) then
      WorldApi.markUnscripted(w, "UnitDetailedThreatSituation")
      return
    end
    return M.situation(w, enemy, source)
  end)
end

return M
