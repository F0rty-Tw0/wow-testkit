-- SimState: a sim world as plain data and back, for a hot reload (session_sim.lua carries it to the fresh world). export
-- reads the clock, the player and the other actors with their auras and fights, the group, the held keys and every state a
-- unit registered with persist; restore puts it back in phase 2 of the fresh world's install. A cast or a channel is never
-- kept: the reload ends it, and no UNIT_SPELLCAST_STOP is sent for it.
local M = {}

local Actors = require("combat_actors")
local Ai = require("combat_ai")
local Auras = require("combat_auras")
local GameState = require("game.state")
local Group = require("combat_group")
local Nameplates = require("combat_nameplates")
local SimMove = require("sim_move")
local State = require("combat_state")

local VERSION = 1
local MOUSEOVER = "mouseover"

local function copy(t)
  return GameState.merge({}, t)
end

-- The GUIDs of a set { [guid] = true }, sorted.
local function guidList(set)
  local out = {}
  for guid in pairs(set or {}) do
    out[#out + 1] = guid
  end
  table.sort(out)

  return out
end

local function exportActor(actor)
  return {
    guid = actor.guid,
    kind = actor.kind,
    name = actor.name,
    level = actor.level,
    hostile = actor.isEnemy == true,
    npcId = actor.npcId,
    pos = copy(actor.pos),
    facing = actor.facing,
    health = actor.health,
    healthMax = actor.healthMax,
    power = actor.power,
    powerMax = actor.powerMax,
    powerToken = actor.powerToken,
    dead = actor.isDead,
    auras = copy(actor.auras),
    auraSeq = actor.auraSeq,
    ai = actor.ai and copy(actor.ai),
    foes = guidList(actor.foes),
    swings = actor.swings,
    className = actor.className,
    classFile = actor.classFile,
  }
end

local function exportPlayer(player)
  return {
    guid = player.guid,
    pos = copy(player.pos),
    facing = player.facing,
    health = player.health,
    healthMax = player.healthMax,
    power = player.power,
    powerMax = player.powerMax,
    auras = copy(player.auras),
    auraSeq = player.auraSeq,
    targetGuid = player.targetGuid,
  }
end

-- The roster, or { kind } for a group kind a state request set with no roster behind it, or nil when the player is in no
-- group.
local function exportGroup(w)
  local g = w.combat.group
  if not g then
    return w.mock.group ~= "none" and { kind = w.mock.group } or nil
  end
  local members = {}
  for i, actor in ipairs(g.members) do
    members[i] = actor.guid
  end

  return { raid = g.raid, leader = w.mock.leader, members = members }
end

-- KEY -> the command its down resolved, for every held key that ran one.
local function exportHeld(w)
  local out = {}
  for key, held in pairs(w.input.heldKeys) do
    out[key] = held.command or nil
  end

  return out
end

local function exportExt(w)
  local out = {}
  for key, spec in pairs(w.sim.hooks.persist) do
    out[key] = spec.export(w)
  end

  return out
end

-- The world w as plain data: numbers, strings, booleans and tables, no table twice, no function.
function M.export(w)
  local c, sim = w.combat, w.sim
  local actors = {}
  for _, guid in ipairs(c.order) do
    local actor = c.actors[guid]
    if actor ~= sim.player then
      actors[#actors + 1] = exportActor(actor)
    end
  end
  local mouseover = Actors.get(w, MOUSEOVER)
  local state = {
    version = VERSION,
    class = sim.class,
    level = sim.level,
    now = w.now,
    t0 = c.t0,
    carry = sim.clock.carry,
    seq = c.seq,
    intents = copy(sim.intents),
    held = exportHeld(w),
    player = exportPlayer(sim.player),
    actors = actors,
    group = exportGroup(w),
    mouseover = mouseover and mouseover.guid,
    combat = { flag = w.mock.combat == true, dropIn = State.dropIn(w) },
    ext = exportExt(w),
  }

  return state
end

-- Registers a unit's own state for a reload: spec = { export = fn(w) -> plain data, restore = fn(w, data) }. export runs
-- on the old world (its data sits under state.ext[key]); restore runs on the fresh world, which registers in its install.
function M.persist(w, key, spec)
  local valid = type(key) == "string" and type(spec) == "table"
  if not (valid and type(spec.export) == "function" and type(spec.restore) == "function") then
    error("Sim.persist: needs a string key and { export = function, restore = function }", 2)
  end
  w.sim.hooks.persist[key] = spec
end

-- Moves the fresh world's clock to the saved one: every pending timer keeps its time left, so no timer fires before now
-- and GetTime and the combat log's timestamps go on from where they were.
local function resumeClock(w, state)
  local shift = state.now - w.now
  for _, timer in ipairs(w.timers) do
    timer.due = timer.due + shift
  end
  w.now = state.now
  w.combat.t0 = state.t0
  w.sim.clock.carry = state.carry
end

-- The player's place, class, level, health, power and auras, set without hooks; the saved class wins over the session's.
local function restorePlayer(w, state)
  local sim, saved = w.sim, state.player
  local player = sim.player
  require("sim").applyClass(w, player, state.class)
  sim.class, sim.level, player.level = state.class, state.level, state.level
  player.pos.x, player.pos.y = saved.pos.x, saved.pos.y
  player.facing = saved.facing
  player.healthMax, player.health = saved.healthMax, saved.health
  player.powerMax, player.power = saved.powerMax, saved.power
  Auras.restore(w, player, saved)
end

local function restoreActor(w, saved)
  local actor = Actors.add(w, {
    guid = saved.guid,
    kind = saved.kind,
    name = saved.name,
    level = saved.level,
    hostile = saved.hostile,
    npcId = saved.npcId,
    pos = saved.pos,
    health = saved.health,
    healthMax = saved.healthMax,
    power = saved.power,
    powerMax = saved.powerMax,
    powerType = saved.powerToken,
    className = saved.className,
    classFile = saved.classFile,
  })
  actor.facing, actor.isDead, actor.swings = saved.facing, saved.dead, saved.swings
  actor.ai = saved.ai and copy(saved.ai)
  Auras.restore(w, actor, saved)

  return actor
end

-- Re-adds every saved actor; returns GUID -> actor, the player included.
local function restoreActors(w, state)
  local byGuid = { [state.player.guid] = w.sim.player }
  for _, saved in ipairs(state.actors) do
    byGuid[saved.guid] = restoreActor(w, saved)
  end

  return byGuid
end

-- A saved roster is set again and a saved kind with no roster is set as the kind alone; a world saved in no group clears
-- the group a session state gave the fresh one.
local function restoreGroup(w, g, byGuid)
  if not g then
    Group.clear(w)
  elseif not g.members then
    w:setMock({ group = g.kind })
  else
    local members = {}
    for i, guid in ipairs(g.members) do
      members[i] = byGuid[guid]
    end
    Group.set(w, members, { raid = g.raid, leader = g.leader })
  end
end

local function restoreBindings(w, state, byGuid)
  restoreGroup(w, state.group, byGuid)
  Actors.setTarget(w, w.sim.player, byGuid[state.player.targetGuid])
  local mouseover = byGuid[state.mouseover]
  if mouseover then
    Actors.bind(w, mouseover, MOUSEOVER)
  end
end

local function hasLiveHostileFoe(w, actor)
  for guid in pairs(actor.foes or {}) do
    local foe = w.combat.actors[guid]
    if foe and foe.isEnemy and not foe.isDead then
      return true
    end
  end

  return false
end

-- The fights again, then the AI of every fighting actor that has one (its timers start over from now); a player still in
-- combat with no live hostile foe gets the drop that was pending, and a player out of combat leaves a combat the session
-- state turned on.
local function restoreCombat(w, state, byGuid)
  for _, saved in ipairs(state.actors) do
    for _, guid in ipairs(saved.foes) do
      local foe = byGuid[guid]
      if foe then
        State.engage(w, byGuid[saved.guid], foe)
      end
    end
  end
  for _, saved in ipairs(state.actors) do
    local actor = byGuid[saved.guid]
    if actor.ai and actor.affectingCombat then
      Ai.start(w, actor)
    end
  end
  local flag = state.combat.flag
  if flag and not hasLiveHostileFoe(w, w.sim.player) then
    State.restoreDrop(w, state.combat.dropIn)
  elseif not flag and w.mock.combat then
    State.restoreOff(w)
  end
end

-- source: assumed (row SM15) a key held across a reload stays held: the walk goes on, and the viewer's keyup (which runs
-- the command's up half) stops it. Only the command is kept; the frames its down reached are gone with the old world.
local function restoreInput(w, state)
  SimMove.set(w, state.intents)
  for key, command in pairs(state.held) do
    w.input.heldKeys[key] = { reached = {}, command = command }
  end
end

local function restoreExt(w, state)
  for key, data in pairs(state.ext) do
    local spec = w.sim.hooks.persist[key]
    if spec then
      spec.restore(w, data)
    end
  end
end

-- Puts an exported world back on the fresh sim world w (phase 2, after the session state and the bindings).
function M.restore(w, state)
  resumeClock(w, state)
  restorePlayer(w, state)
  local byGuid = restoreActors(w, state)
  w.combat.seq = state.seq
  restoreBindings(w, state, byGuid)
  restoreCombat(w, state, byGuid)
  restoreInput(w, state)
  restoreExt(w, state)
  Nameplates.sync(w)
end

return M
