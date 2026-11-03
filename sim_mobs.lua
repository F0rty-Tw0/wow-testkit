-- SimMobs: the sim world's hostile mobs. spawn and pack put them in front of the player; each sim frame an idle mob that
-- sees the player (inside the aggro radius and its front 180 degrees) or already fights the player engages, pulls the idle
-- mobs near it (transitively), and chases its top-threat target until the target is in melee range. Its swings are the
-- combat AI's (combat_ai.lua) with a gate (in range, not stunned) and a counter.
-- actor.mobState is "idle" or "engaged" (hostile mobs only); actor.swings counts landed swings; actor.loot is Task 4.2's.
local M = {}

local Actors = require("combat_actors")
local Ai = require("combat_ai")
local GameState = require("game.state")
local SimMelee = require("sim_melee")
local SimRange = require("sim_range")
local SimState = require("sim_state")
local State = require("combat_state")
local Threat = require("combat_threat")

local atan2 = math.atan2 or math.atan

local IDLE = "idle"
local ENGAGED = "engaged"

-- source: assumed (spec 5.3) the mob rules in yards, yards per second and whole mobs; the distances are measured after both
-- reaches. A real mob's numbers come from creature data the kit does not have.
M.RULES = { aggro = 10, social = 8, chase = 7, ahead = 20, gap = 3, maxPack = 10 }

-- Kit mobs hit lightly (spec 5.7).
-- source: assumed (spec 5.7) a default mob swings for 3 every 2 seconds; the kit has no creature data.
local function defaultAi()
  local rule = { every = 2, damage = 3 }

  return { swing = rule }
end

local OPTION_TYPES = { name = "string", level = "number", health = "number", hostile = "boolean" }
local POSITIVE = { "level", "health" }

-- Level 0: no file position, so the message reads the same through a script, a scenario and the session's reply.
local function fail(fmt, ...)
  error(string.format("SimMobs.spawn: " .. fmt, ...), 0)
end

local function validPos(pos)
  return type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
end

-- Raises for a repeating rule (ai.swing, or one of ai.spells) that Ai.start would refuse or run into later.
local function checkRule(rule, name)
  if type(rule) ~= "table" then
    fail("%s must be a table", name)
  end
  local problem = Ai.ruleError(rule)
  if problem then
    fail("%s: %s", name, problem)
  end
end

local function checkAi(ai)
  if ai == nil or ai == false then
    return
  end
  if type(ai) ~= "table" then
    fail("ai must be a table or false")
  end
  if ai.swing ~= nil then
    checkRule(ai.swing, "ai.swing")
    if type(ai.swing.damage) ~= "number" then
      fail("ai.swing.damage must be a number")
    end
  end
  for index, rule in ipairs(ai.spells or {}) do
    checkRule(rule, "ai.spells[" .. index .. "]")
  end
end

-- Raises "SimMobs.spawn: <field> must be a <type>" (or an above-0 number for level and health, or a runnable ai) for a bad
-- option. spawn and pack run it before anything is added, so a refused mob leaves no actor behind.
local function check(opts)
  for field, kind in pairs(OPTION_TYPES) do
    local value = opts[field]
    local wrongType = value ~= nil and type(value) ~= kind
    if wrongType then
      fail("%s must be a %s", field, kind)
    end
  end
  for _, field in ipairs(POSITIVE) do
    local value = opts[field]
    if value ~= nil and value <= 0 then
      fail("%s must be a number above 0", field)
    end
  end
  local badPos = opts.pos ~= nil and not validPos(opts.pos)
  if badPos then
    fail("pos must be a table with a number x and y")
  end
  checkAi(opts.ai)
end

-- The direction an actor faces to look at the point (x, y): 0 is north, turning counter-clockwise; forward is (-sin, cos).
local function facingAt(from, x, y)
  return atan2(from.pos.x - x, y - from.pos.y)
end

-- The point `yards` ahead of the player along its facing.
local function ahead(player, yards)
  local facing = player.facing or 0

  local point = { x = player.pos.x - math.sin(facing) * yards, y = player.pos.y + math.cos(facing) * yards }

  return point
end

-- The rule table a mob gets: nil is the default, false is none (a dummy), a table is copied (the rule gets the gate).
local function aiFor(given)
  if given == nil then
    return defaultAi()
  end
  if not given then
    return nil
  end

  return GameState.merge({}, given)
end

local function hasAura(actor, field)
  for _, aura in ipairs(actor.auras) do
    if aura[field] then
      return true
    end
  end

  return false
end

-- Whether mob's swing lands on target now: in melee range and not stunned.
-- source: assumed (spec 5.3) a stun stops a mob's swings; a root does not.
function M.canSwing(_, mob, target)
  local inRange = SimMelee.inRange(mob, target)

  return inRange and not hasAura(mob, "stun")
end

local function countSwing(_, mob)
  mob.swings = (mob.swings or 0) + 1
end

-- Puts the gate and the counter on the mob's swing rule (they are functions, so a reload does not keep them).
function M.rearm(_, actor)
  local swing = actor.ai and actor.ai.swing
  if swing then
    swing.gate, swing.onSwing = M.canSwing, countSwing
  end
end

-- Adds the mob that check already passed.
local function build(w, given)
  local player = w.sim.player
  local hostile = given.hostile ~= false
  local level = given.level or player.level
  local pos = given.pos or ahead(player, M.RULES.ahead)
  local mob = Actors.add(w, {
    kind = "npc",
    name = given.name or "Training Foe",
    hostile = hostile,
    level = level,
    health = given.health or 10 * level,
    pos = pos,
  })
  mob.facing = facingAt(mob, player.pos.x, player.pos.y)
  mob.loot = given.loot
  mob.mobState = hostile and IDLE or nil
  mob.ai = aiFor(given.ai)
  M.rearm(w, mob)

  return mob
end

-- Adds a mob. opts = { name?, level?, health?, hostile?, pos?, loot?, ai? }: see the defaults in the module's header. Raises
-- "SimMobs.spawn: <field> must be a <type>" (see check) before the mob is built.
function M.spawn(w, opts)
  local given = opts or {}
  check(given)

  return build(w, given)
end

-- n mobs (1 to RULES.maxPack) in a row along the player's right, RULES.gap apart, centred on opts.pos or the default point.
function M.pack(w, n, opts)
  local max = M.RULES.maxPack
  local badSize = type(n) ~= "number" or n < 1 or n > max or n ~= math.floor(n)
  if badSize then
    error(string.format("SimMobs.pack: n must be a whole number 1-%d", max), 0)
  end
  local base = opts or {}
  check(base)
  local player = w.sim.player
  local facing = player.facing or 0
  local centre = base.pos or ahead(player, M.RULES.ahead)
  local mobs = {}
  for i = 1, n do
    local offset = (i - (n + 1) / 2) * M.RULES.gap
    local given = GameState.merge({}, base)
    given.pos = { x = centre.x + math.cos(facing) * offset, y = centre.y + math.sin(facing) * offset }
    mobs[i] = build(w, given)
  end

  return mobs
end

-- Marks the mob engaged and fights the player and the player's group; its AI starts, and it leads no threat list but
-- the player's at 0. Ai.pull would start every actor's AI, so the mob starts its own.
local function engage(w, mob)
  local player = w.sim.player
  mob.mobState = ENGAGED
  State.engage(w, mob, player)
  local group = w.combat.group
  local members = group and group.members or {}
  for _, member in ipairs(members) do
    if member ~= player then
      State.engage(w, mob, member)
    end
  end
  Threat.add(w, mob, player, 0)
  Ai.start(w, mob)
end

local function canBePulled(mob)
  return mob.mobState == IDLE and mob.ai ~= nil and not mob.isDead
end

-- Engages every idle mob within RULES.social of an engaged one, starting from first; the pulled ones pull too.
local function pull(w, first)
  local queue, head = { first }, 1
  while queue[head] do
    local from = queue[head]
    head = head + 1
    for _, guid in ipairs(w.combat.order) do
      local other = w.combat.actors[guid]
      local pullable = canBePulled(other)
      local close = pullable and SimRange.distance(from, other) <= M.RULES.social
      if close then
        engage(w, other)
        queue[#queue + 1] = other
      end
    end
  end
end

local function fightsPlayer(mob, player)
  return mob.foes ~= nil and mob.foes[player.guid] == true
end

-- source: assumed (spec 5.3) a mob with an AI sees the player inside the aggro radius and its own front 180 degrees; a
-- dummy (no AI) sees nothing.
local function seesPlayer(mob, player)
  if mob.ai == nil then
    return false
  end
  local close = SimRange.distance(mob, player) <= M.RULES.aggro
  local inFront = SimRange.inFront(mob, player)

  return close and inFront
end

-- Walks the engaged mob toward its target, facing it, and stops in melee range. A root stops the walk; a stun also
-- stops the turn.
-- source: assumed (spec 5.3) a stunned mob cannot walk or turn, a rooted one cannot walk but still turns.
local function chase(w, mob, dt)
  local target = Ai.target(w, mob)
  if not target or hasAura(mob, "stun") then
    return
  end
  mob.facing = facingAt(mob, target.pos.x, target.pos.y)
  local rooted = hasAura(mob, "root")
  if rooted or SimMelee.inRange(mob, target) then
    return
  end
  local dx, dy = target.pos.x - mob.pos.x, target.pos.y - mob.pos.y
  local length = math.sqrt(dx * dx + dy * dy)
  local step = math.min(M.RULES.chase * dt, SimRange.distance(mob, target) - SimMelee.RANGE)
  Actors.setPos(w, mob, mob.pos.x + dx / length * step, mob.pos.y + dy / length * step)
end

-- One sim frame: an idle mob that wakes engages and pulls its neighbours; an engaged mob with an AI chases.
function M.step(w, dt)
  local player = w.sim.player
  for _, guid in ipairs(w.combat.order) do
    local mob = w.combat.actors[guid]
    local canWake = mob.mobState == IDLE and not mob.isDead
    local wakes = canWake and (fightsPlayer(mob, player) or seesPlayer(mob, player))
    if wakes then
      engage(w, mob)
      pull(w, mob)
    end
    if mob.mobState == ENGAGED and mob.ai and not mob.isDead then
      chase(w, mob, dt)
    end
  end
end

-- Each mob's state a reload keeps: { [guid] = { mobState, loot } }.
local function export(w)
  local out = {}
  for _, guid in ipairs(w.combat.order) do
    local mob = w.combat.actors[guid]
    if mob.mobState or mob.loot ~= nil then
      out[guid] = { mobState = mob.mobState, loot = mob.loot }
    end
  end

  return out
end

local function restore(w, data)
  for guid, saved in pairs(data) do
    local mob = w.combat.actors[guid]
    if mob then
      mob.mobState, mob.loot = saved.mobState, saved.loot
      M.rearm(w, mob)
    end
  end
end

function M.install(w)
  -- source: assumed (spec 5.7): mobs cannot kill the sim player; install runs on every reopened world, so a reload keeps it.
  w.sim.player.healthFloor = 1
  table.insert(w.sim.hooks.frame, M.step)
  SimState.persist(w, "mobs", { export = export, restore = restore })
end

return M
