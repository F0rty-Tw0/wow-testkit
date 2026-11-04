-- SimWorld: the sim world as a viewer or a script reads it, one plain table per call: the player, every other combat actor
-- in spawn order, the effects list (SimEffects.snapshot) and the ground targeting mode. Pure reads; positions and lists are copies.
local M = {}

local SimEffects = require("sim_effects")
local SimRange = require("sim_range")

local function spellIds(actor)
  local ids = {}
  for i, aura in ipairs(actor.auras) do
    ids[i] = aura.spellId
  end

  return ids
end

-- The cast bar in flight as plain data ({ spellID, start, endTime } in clock seconds), or nil.
local function castOf(player)
  local casting = player.casting

  return casting and { spellID = casting.spellID, start = casting.start, endTime = casting.endTime } or nil
end

local function playerEntry(w)
  local sim = w.sim
  local player = sim.player

  return {
    guid = player.guid,
    pos = SimRange.copy(player.pos),
    facing = player.facing or 0,
    moving = sim.moving,
    health = player.health,
    healthMax = player.healthMax,
    power = player.power,
    powerMax = player.powerMax,
    class = player.classFile,
    swings = player.swings or 0,
    casting = castOf(player),
  }
end

local function actorEntry(w, actor)
  local targetGuid = w.sim.player.targetGuid

  return {
    guid = actor.guid,
    name = actor.name,
    kind = actor.kind,
    pos = SimRange.copy(actor.pos),
    facing = actor.facing or 0,
    health = actor.health,
    healthMax = actor.healthMax,
    dead = actor.isDead == true,
    hostile = actor.isEnemy == true,
    lootable = actor.lootable == true,
    isTarget = targetGuid ~= nil and actor.guid == targetGuid,
    isMouseover = w.unitState.byToken.mouseover == actor,
    auras = spellIds(actor),
    class = actor.classFile,
    swings = actor.swings or 0,
  }
end

-- The targeting mode as plain data ({ spellID, radius }), or nil.
local function targetingOf(w)
  local mode = w.sim.targeting

  return mode and { spellID = mode.spellID, radius = mode.radius } or nil
end

-- { player, actors, effects, targeting } of w, which must hold a sim.
function M.build(w)
  local c = w.combat
  local actors = {}
  for _, guid in ipairs(c.order) do
    local actor = c.actors[guid]
    if actor ~= w.sim.player then
      actors[#actors + 1] = actorEntry(w, actor)
    end
  end

  return { player = playerEntry(w), actors = actors, effects = SimEffects.snapshot(w), targeting = targetingOf(w) }
end

return M
