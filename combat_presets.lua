-- Presets: a solo, dungeon or raid world built from combat_roster_data.lua. Presets.apply replaces the previous preset (its
-- group, members and enemies), configures the player (faction, race, class, role, level, full health, alive), fills the group with actors named
-- "Kit <Class> <n>" whose classes cycle by role, spawns the enemy pack with behaviour rules, and starts nothing unless
-- opts.inCombat is set. Every number comes from the roster data (R4).
local M = {}

local Actors = require("combat_actors")
local Ai = require("combat_ai")
local Combat = require("combat")
local Group = require("combat_group")
local Resolve = require("combat_resolve")
local Roster = require("combat_roster_data")

local PLAYER = "player"
local PRESETS = { "solo", "dungeon", "raid" }
local INSTANCE_TYPES = { solo = "none", dungeon = "party", raid = "raid" }
local FACTIONS = { "Alliance", "Horde" }
local DEFAULT = { faction = "Alliance", class = "WARRIOR", role = "DAMAGER", size = 10 }

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, item in pairs(value) do
    out[key] = copy(item)
  end
  return out
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

-- "a, b or c" for a list of strings or numbers.
local function orList(values)
  local parts = {}
  for i, value in ipairs(values) do
    parts[i] = tostring(value)
  end
  if #parts < 2 then
    return parts[1] or ""
  end
  return table.concat(parts, ", ", 1, #parts - 1) .. " or " .. parts[#parts]
end

local function invalid(fmt, ...)
  return "preset: " .. string.format(fmt, ...)
end

local function raceNamed(list, name)
  for _, race in ipairs(list) do
    if race.name == name then
      return race
    end
  end
end

-- The settings a preset call asks for with the defaults filled in, { name, size?, faction, race = { name, file }, class,
-- role, level, inCombat }. Raises "preset: <valid values>" at the caller's caller (level 3), so a scenario's call is blamed.
function M.resolve(w, name, opts)
  opts = opts or {}
  local out = { name = name, inCombat = opts.inCombat == true }
  if not Roster.PACKS[name] then
    error(invalid("unknown preset '%s'; valid: %s", tostring(name), orList(PRESETS)), 3)
  end
  if name == "raid" then
    out.size = opts.size or DEFAULT.size
    if not contains(Roster.SIZES, out.size) then
      error(invalid("size must be %s, got %s", orList(Roster.SIZES), tostring(out.size)), 3)
    end
  end
  out.faction = opts.faction or DEFAULT.faction
  if not contains(FACTIONS, out.faction) then
    error(invalid("faction must be %s, got '%s'", orList(FACTIONS), tostring(out.faction)), 3)
  end
  out.class = opts.class or DEFAULT.class
  if not contains(Roster.CLASSES[w.flavor], out.class) then
    error(invalid("class '%s' is not on %s; valid: %s", tostring(out.class), w.flavor, orList(Roster.CLASSES[w.flavor])), 3)
  end
  local races = Roster.RACES[w.flavor][out.faction]
  out.race = opts.race == nil and races[1] or raceNamed(races, opts.race)
  if not out.race then
    local names = {}
    for i, race in ipairs(races) do
      names[i] = race.name
    end
    error(invalid("race '%s' is not a %s race on %s; valid: %s", tostring(opts.race), out.faction, w.flavor, orList(names)), 3)
  end
  out.role = opts.role or DEFAULT.role
  if not contains(Roster.ROLES, out.role) then
    error(invalid("role must be %s, got '%s'", orList(Roster.ROLES), tostring(out.role)), 3)
  end
  out.level = opts.level or Roster.LEVELS[w.flavor]
  if type(out.level) ~= "number" then
    error(invalid("level must be a number, got %s", type(out.level)), 3)
  end
  return out
end

-- The classes of a role that the flavor has, in cycling order.
local function classPool(flavor, role)
  local pool = {}
  for _, class in ipairs(Roster.ROLE_CLASSES[role]) do
    if contains(Roster.CLASSES[flavor], class) then
      pool[#pool + 1] = class
    end
  end
  return pool
end

local function dress(actor, o, class, race, role)
  actor.className, actor.classFile = Roster.CLASS_NAMES[class], class
  actor.raceName, actor.raceFile, actor.faction = race.name, race.file, o.faction
  actor.level, actor.role = o.level, role
  actor.threatMod = Roster.MEMBERS[role].threatMod
end

-- A dead or ghost player comes back at full health through Resolve.revive, which emits the "flags" hook.
local function configurePlayer(w, player, o)
  dress(player, o, o.class, o.race, o.role)
  local health = Roster.MEMBERS[o.role].health
  Actors.setHealthMax(w, player, health)
  if not Resolve.revive(w, player, health) then
    Actors.setHealth(w, player, health)
  end
end

-- The roster in order: the player, then the tanks, healers and damage dealers the mix still needs.
local function buildMembers(w, player, o)
  local members = { player }
  -- source: confirmed (row C11) a role is TANK, HEALER, DAMAGER or NONE; the roster's roles come from the mix in the data.
  if o.name == "solo" then
    return members
  end
  local mix = copy(Roster.ROLE_MIX[o.size or o.name])
  mix[o.role] = mix[o.role] - 1
  local races = Roster.RACES[w.flavor][o.faction]
  for _, role in ipairs(Roster.ROLES) do
    local pool = classPool(w.flavor, role)
    for i = 1, mix[role] do
      local n = #members
      local class = pool[(i - 1) % #pool + 1]
      local actor = Actors.add(w, {
        kind = "player",
        name = string.format("Kit %s %d", Roster.CLASS_NAMES[class], n),
        health = Roster.MEMBERS[role].health,
      })
      dress(actor, o, class, races[(n - 1) % #races + 1], role)
      actor.ai = copy(Roster.MEMBERS[role].ai)
      members[#members + 1] = actor
    end
  end
  return members
end

local function spawnEnemies(w, o)
  local enemies = {}
  for i, entry in ipairs(Roster.PACKS[o.name]) do
    local enemy = Actors.add(w, {
      kind = "npc",
      name = entry.name,
      token = entry.token,
      hostile = true,
      health = entry.health,
      level = o.level,
      pos = entry.pos,
    })
    enemy.ai = copy(entry.ai)
    enemies[i] = enemy
  end
  return enemies
end

-- Takes the previous preset out of the world: the group first (one roster event), then its actors, the player excepted.
local function clearPrevious(w)
  local previous = w.combat.preset
  Group.clear(w)
  for _, list in ipairs({ previous and previous.members or {}, previous and previous.enemies or {} }) do
    for _, actor in ipairs(list) do
      if actor ~= w.unitState.byToken[PLAYER] then
        Actors.remove(w, actor)
      end
    end
  end
  w.combat.preset = nil
end

-- name: "solo", "dungeon" or "raid"; opts = { size? (raid: 10, 20, 25 or 40; 10), faction? = "Alliance", race? (the first of
-- the faction's races on the flavor), class? = "WARRIOR", role? = "DAMAGER", level? (per flavor), inCombat? = false }.
-- Returns { player, members (the player first), enemies } and keeps it as w.combat.preset. inCombat pulls the whole pack.
function M.apply(w, name, opts)
  local o = M.resolve(w, name, opts)
  local c = Combat.install(w)
  clearPrevious(w)
  -- A dungeon is a party instance and a raid a raid instance (IsInInstance reads this store); solo is the open world.
  w:setMock({ instance = { type = INSTANCE_TYPES[o.name] } })
  for id, spell in pairs(Roster.SPELLS) do
    c.spells[id] = c.spells[id] or copy(spell)
  end
  local player = Actors.get(w, PLAYER)
  configurePlayer(w, player, o)
  local members = buildMembers(w, player, o)
  if #members > 1 then
    -- source: confirmed (row C11) GROUP_ROSTER_UPDATE fires when a group forms; assumed (row C11) a raid has no party# tokens.
    Group.set(w, members, { raid = o.name == "raid" })
  end
  local preset = { player = player, members = members, enemies = spawnEnemies(w, o) }
  c.preset = preset
  if o.inCombat then
    for _, enemy in ipairs(preset.enemies) do
      Ai.pull(w, enemy)
    end
  end
  return preset
end

return M
