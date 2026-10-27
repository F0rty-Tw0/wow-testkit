-- Combat state: who is engaged with whom, and the player's combat. First hostile contact for the player fires
-- PLAYER_REGEN_DISABLED, then sets w.mock.combat (what InCombatLockdown reads); when no live hostile foe remains, the
-- drop comes c.dropDelay seconds later: w.mock.combat is cleared, then PLAYER_REGEN_ENABLED fires. Engaged actors carry
-- affectingCombat, which UnitAffectingCombat reads.
local M = {}

local Combat = require("combat")

local PLAYER = "player"
-- source: assumed (row C10) the client drops combat a few seconds after the last hostile contact.
local DROP_DELAY = 5

local function player(w)
  return w.unitState.byToken[PLAYER]
end

local function foesOf(actor)
  actor.foes = actor.foes or {}
  return actor.foes
end

local function check(w, actor, name)
  if type(actor) ~= "table" or w.combat.actors[actor.guid] ~= actor then
    error("State." .. name .. ": not an actor of this world", 3)
  end
end

-- Sets the actor's combat flag; true when it changed.
local function setFlag(actor, on)
  local changed = (actor.affectingCombat == true) ~= on
  actor.affectingCombat = on
  return changed
end

local function announce(w, actor, changed)
  if changed then
    Combat.emit(w, "flags", actor)
  end
end

-- True when the actor has a hostile foe in the world; a foe that dies or despawns is disengaged by its hooks.
local function hasHostileFoe(w, actor)
  for guid in pairs(foesOf(actor)) do
    local foe = w.combat.actors[guid]
    if foe and foe.isEnemy then
      return true
    end
  end
  return false
end

local fire = Combat.fire

local function dropNow(w)
  local c, p = w.combat, player(w)
  c.dropTimer = nil
  if not w.mock.combat or (p and hasHostileFoe(w, p)) then
    return
  end
  local changed = p and setFlag(p, false)
  -- source: confirmed (row G8) lockdown ends before PLAYER_REGEN_ENABLED fires.
  w:setMock({ combat = false })
  fire(w, "PLAYER_REGEN_ENABLED")
  if p then
    announce(w, p, changed)
  end
end

-- Starts the drop timer once the player has no live hostile foe left; a timer already running keeps its time.
local function scheduleDrop(w)
  local c = w.combat
  if w.mock.combat and not c.dropTimer then
    c.dropTimer = Combat.later(w, c.dropDelay, function()
      dropNow(w)
    end)
  end
end

local function cancelDrop(c)
  if c.dropTimer then
    c.dropTimer:Cancel()
    c.dropTimer = nil
  end
end

-- Marks a and b as fighting each other. Contact between the player and a hostile actor starts the player's combat
-- (unless w.mock.combat is already on) and cancels a pending drop; every newly engaged actor gets affectingCombat and
-- a "flags" hook. Other pairs, a party member's fight included, only set affectingCombat. A dead actor engages no one.
function M.engage(w, a, b)
  check(w, a, "engage")
  check(w, b, "engage")
  if a.isDead or b.isDead then
    return
  end
  local p = player(w)
  local first, second = a, b
  if b == p then
    first, second = b, a
  end
  foesOf(first)[second.guid], foesOf(second)[first.guid] = true, true
  if first == p and second.isEnemy then
    local c = w.combat
    cancelDrop(c)
    if not w.mock.combat then
      -- source: confirmed (row G8) lockdown begins after PLAYER_REGEN_DISABLED fires.
      fire(w, "PLAYER_REGEN_DISABLED")
      w:setMock({ combat = true })
    end
  end
  local changed = { setFlag(first, true), setFlag(second, true) }
  announce(w, first, changed[1])
  announce(w, second, changed[2])
end

-- Takes the actor out of every fight it is in. Foes left with no foe stop affecting combat; when that leaves the
-- player with no live hostile foe, the drop timer starts.
function M.disengage(w, actor)
  check(w, actor, "disengage")
  local p = player(w)
  local touchesPlayer = actor == p or (p ~= nil and foesOf(p)[actor.guid] == true)
  for guid in pairs(foesOf(actor)) do
    local foe = w.combat.actors[guid]
    if foe then
      foesOf(foe)[actor.guid] = nil
      announce(w, foe, next(foesOf(foe)) == nil and setFlag(foe, false))
    end
  end
  actor.foes = {}
  announce(w, actor, setFlag(actor, false))
  if touchesPlayer and p and not hasHostileFoe(w, p) then
    scheduleDrop(w)
  end
end

function M.install(w)
  w.combat.dropDelay = DROP_DELAY
  local function leave(actor)
    M.disengage(w, actor)
  end
  Combat.listen(w, "death", leave)
  Combat.listen(w, "despawn", leave)
end

return M
