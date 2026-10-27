-- Actors: the combat world's units. An actor is its own unit fixture (w:unit(token, actor)), so the Unit* answers read
-- its fields live and a setter's change is visible to the next API call. Tokens are bindings from the unit state;
-- an actor may hold several. Setters clamp, change the actor and emit the combat hook only when the value changed.
local M = {}

local Combat = require("combat")
local State = require("game.state")
local Units = require("units")

local SERVER = 4001
local INSTANCE = 1
local ZONE = 1000
local DEFAULT_MAX = 100
-- source: assumed (rows G11, C6) the kit's reaction numbers: 2 is hostile and 5 is friendly on the UnitReaction scale.
local HOSTILE, FRIENDLY = 2, 5
local DEFAULT_POWER = "MANA"
local PLAYER_NAME = "Player"
local PLAYER, TARGET = "player", "target"

-- kind -> the GUID type.
local GUID_TYPES = { player = "Player", arena = "Player", npc = "Creature", boss = "Creature", pet = "Pet" }
local KIND_LIST = "arena, boss, npc, pet, player"

-- Fields every actor holds; State.fill keeps what the spec or an adopted fixture already set.
local DEFAULTS = { auras = {}, absorbs = 0, isDead = false, inParty = false, inRaid = false, pos = { x = 0, y = 0 } }

-- source: confirmed (row C6) Creature GUIDs are Creature-0-<server>-<instance>-<zone>-<npcId>-<10 hex>; assumed Player
-- GUIDs end in 8 hex digits and a Pet GUID has the Creature shape.
local function newGuid(c, kind, npcId)
  c.seq = c.seq + 1
  local guidType = GUID_TYPES[kind]
  if guidType == "Player" then
    return string.format("Player-%d-%08X", SERVER, c.seq)
  end
  return string.format("%s-0-%d-%d-%d-%d-%010X", guidType, SERVER, INSTANCE, ZONE, npcId, c.seq)
end

-- source: confirmed (row C6) a cast GUID is Cast-3-<server>-<instance>-<zone>-<spellId>-<10 hex>; assumed the fields
-- after Cast-3 are the actor GUIDs' server, instance and zone.
function M.newCastGuid(w, spellID)
  local c = w.combat
  c.seq = c.seq + 1
  return string.format("Cast-3-%d-%d-%d-%d-%010X", SERVER, INSTANCE, ZONE, spellID, c.seq)
end

-- Enum.PowerType's number for a power token ("RUNIC_POWER" -> Enum.PowerType.RunicPower), nil when the world has none.
local function powerNumber(token)
  local key = token:lower():gsub("_(%a)", string.upper):gsub("^%a", string.upper)
  local enum = _G.Enum and _G.Enum.PowerType
  return enum and enum[key]
end

local function number(value, what)
  if type(value) ~= "number" then
    error("combat: " .. what .. " must be a number, got " .. type(value), 3)
  end
  return value
end

local function clamp(value, max)
  return math.max(0, math.min(value, max or math.huge))
end

-- Token test order, ties by name.
local function byRank(a, b)
  local rankA, rankB = Units.tokenRank(a) or math.huge, Units.tokenRank(b) or math.huge
  if rankA == rankB then
    return a < b
  end
  return rankA < rankB
end

local function register(c, actor)
  c.actors[actor.guid] = actor
  c.order[#c.order + 1] = actor.guid
end

function M.bind(w, actor, token)
  if w.combat.actors[actor.guid] ~= actor then
    error("Actors.bind: not an actor of this world", 2)
  end
  w:unit(token, actor)
end

function M.unbind(w, token)
  w:unit(token, nil)
end

-- The actor a token or a GUID names, or nil.
function M.get(w, tokenOrGuid)
  local c = w.combat
  if c.actors[tokenOrGuid] then
    return c.actors[tokenOrGuid]
  end
  local data = Units.fixture(w.unitState, tokenOrGuid)
  return data and c.actors[data.guid] == data and data or nil
end

-- Every token bound to actor, in the client's unit-token test order.
function M.tokens(w, actor)
  local tokens = {}
  for token, data in pairs(w.unitState.byToken) do
    if data == actor then
      tokens[#tokens + 1] = token
    end
  end
  table.sort(tokens, byRank)
  return tokens
end

-- spec: { kind, name, token?, hostile?, level?, health?, healthMax?, power?, powerMax?, powerType? = "MANA", className?,
-- classFile?, raceName?, raceFile?, faction?, role?, pos? = { x, y }, npcId? }. Health and power default to their maximum,
-- a maximum to the value given, else 100 health and 0 power.
function M.add(w, spec)
  local c = w.combat
  if not GUID_TYPES[spec.kind] then
    error(string.format("Actors.add: unknown kind '%s'; valid: %s", tostring(spec.kind), KIND_LIST), 2)
  end
  local hostile = spec.hostile == true
  local healthMax = spec.healthMax or spec.health or DEFAULT_MAX
  local powerMax = spec.powerMax or spec.power or 0
  local powerToken = spec.powerType or DEFAULT_POWER
  local actor = {
    kind = spec.kind,
    name = spec.name,
    className = spec.className,
    classFile = spec.classFile,
    raceName = spec.raceName,
    raceFile = spec.raceFile,
    level = spec.level,
    faction = spec.faction,
    role = spec.role,
    npcId = spec.npcId or (1000 + c.seq + 1),
    isPlayer = GUID_TYPES[spec.kind] == "Player",
    reaction = hostile and HOSTILE or FRIENDLY,
    isFriend = not hostile,
    isEnemy = hostile,
    canAttack = hostile,
    healthMax = healthMax,
    health = clamp(spec.health or healthMax, healthMax),
    powerMax = powerMax,
    power = clamp(spec.power or powerMax, powerMax),
    powerToken = powerToken,
    powerType = powerNumber(powerToken),
    pos = spec.pos and { x = spec.pos.x, y = spec.pos.y } or nil,
  }
  actor.guid = newGuid(c, spec.kind, actor.npcId)
  State.fill(actor, DEFAULTS)
  register(c, actor)
  if spec.token then
    M.bind(w, actor, spec.token)
  end
  Combat.emit(w, "spawn", actor)
  return actor
end

-- Takes the actor out of the world: despawn listeners still see its tokens, then every token is unbound.
function M.remove(w, actor)
  local c = w.combat
  if c.actors[actor.guid] ~= actor then
    return
  end
  Combat.emit(w, "despawn", actor)
  for _, token in ipairs(M.tokens(w, actor)) do
    M.unbind(w, token)
  end
  c.actors[actor.guid] = nil
  for i, guid in ipairs(c.order) do
    if guid == actor.guid then
      table.remove(c.order, i)
      break
    end
  end
end

function M.setHealth(w, actor, value)
  local new, old = clamp(number(value, "health"), actor.healthMax), actor.health
  if new ~= old then
    actor.health = new
    Combat.emit(w, "health", actor, old)
  end
end

-- Lowering the maximum below the health lowers the health with it.
function M.setHealthMax(w, actor, value)
  local new, old = math.max(0, number(value, "healthMax")), actor.healthMax
  if new == old then
    return
  end
  actor.healthMax = new
  Combat.emit(w, "healthmax", actor, old)
  M.setHealth(w, actor, actor.health)
end

function M.setPower(w, actor, value)
  local new, old = clamp(number(value, "power"), actor.powerMax), actor.power
  if new ~= old then
    actor.power = new
    Combat.emit(w, "power", actor, actor.powerToken)
  end
end

-- Death emits "death"; coming back to life emits "flags". The dead flag is what UnitIsDead and UnitIsDeadOrGhost read.
function M.setDead(w, actor, dead)
  dead = dead and true or false
  if actor.isDead == dead then
    return
  end
  actor.isDead = dead
  Combat.emit(w, dead and "death" or "flags", actor)
end

-- Points the actor at other (an actor, or nil to clear) and emits "target" with the old GUID when it changed. The player's
-- target also rebinds the "target" token.
function M.setTarget(w, actor, other)
  local old, new = actor.targetGuid, other and other.guid or nil
  if old == new then
    return
  end
  actor.targetGuid = new
  if w.unitState.byToken[PLAYER] == actor then
    if other then
      M.bind(w, other, TARGET)
    else
      M.unbind(w, TARGET)
    end
  end
  Combat.emit(w, "target", actor, old)
end

function M.setPos(w, actor, x, y)
  local pos = actor.pos
  if pos.x == number(x, "x") and pos.y == number(y, "y") then
    return
  end
  pos.x, pos.y = x, y
  Combat.emit(w, "moved", actor)
end

-- Adopts every fixture already bound (the player first, then by token order) and creates the player when none exists.
function M.install(w)
  local c = w.combat
  local byToken = w.unitState.byToken
  local tokens = {}
  for token in pairs(byToken) do
    tokens[#tokens + 1] = token
  end
  table.sort(tokens, byRank)
  for _, token in ipairs(tokens) do
    local data = byToken[token]
    if c.actors[data.guid] ~= data then
      local isPlayer = data.isPlayer or token == PLAYER
      data.kind = isPlayer and "player" or "npc"
      data.isPlayer = isPlayer
      data.npcId = data.npcId or (1000 + c.seq + 1)
      data.guid = newGuid(c, data.kind, data.npcId)
      State.fill(data, DEFAULTS)
      register(c, data)
    end
  end
  if not byToken[PLAYER] then
    M.add(w, { kind = "player", name = PLAYER_NAME, token = PLAYER })
  end
end

return M
