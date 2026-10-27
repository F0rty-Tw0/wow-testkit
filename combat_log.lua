-- Combat log: Log.emit packs one entry per subevent from the layout (combat_log_layout.lua), keeps the newest 1000 in
-- c.log.entries (c.log.seq counts all) and fires COMBAT_LOG_EVENT_UNFILTERED with no payload, as the client does; an addon
-- reads the payload through CombatLogGetCurrentEventInfo during the dispatch. The log is built on every flavor; retail
-- refuses the event to addons (ui/behaviour_scripts.lua, row C1), so only the kit's own readers see it there.
local M = {}

local Layout = require("combat_log_layout")
local Spells = require("combat_spells")
local State = require("game.state")

local unpack = unpack

local ENGINE = "blizzard"
local EVENT = "COMBAT_LOG_EVENT_UNFILTERED"
local RING = 1000
local F = Layout.FLAGS
-- source: assumed (row C3) the kit's school when a spell has none: physical.
local PHYSICAL = 1

-- source: confirmed (row C4) a missing source is GUID "0000000000000000", no name, flags 0x80000000; assumed (row C4) a
-- missing destination is "", no name and flags 0.
local NO_SOURCE = { GUID = "0000000000000000", Flags = F.NONE, RaidFlags = F.NONE }
local NO_DEST = { GUID = "", Flags = 0, RaidFlags = 0 }

-- The seconds on the server clock: GetServerTime's start (w.mock.serverTime) plus the world time since the log began.
function M.timestamp(w)
  return w.mock.serverTime + (w.now - w.combat.t0)
end

-- source: confirmed (row C5) the bit values, the player's 0x511 and the hostile npc's 0xA48 (0x10A48 as the target);
-- assumed (row C5) the party and raid members' 0x512 and 0x514, a friendly npc's 0xA18, the focus bit, a friendly pet as
-- player-controlled, and the raid icon index (actor.raidTarget, 1 to 8) as bit index - 1 of raidFlags.
local TYPE_OF_KIND = { player = F.TYPE_PLAYER, arena = F.TYPE_PLAYER, npc = F.TYPE_NPC, boss = F.TYPE_NPC, pet = F.TYPE_PET }
local PLAYER_KINDS = { player = true, arena = true }
local HOSTILE_REACTION, FRIENDLY_REACTION = 3, 5

-- Returns flags, raidFlags for an actor.
function M.flags(w, actor)
  local byToken = w.unitState.byToken
  local flags
  if byToken.player == actor then
    flags = F.AFFILIATION_MINE
  elseif actor.inRaid then
    flags = F.AFFILIATION_RAID
  elseif actor.inParty then
    flags = F.AFFILIATION_PARTY
  else
    flags = F.AFFILIATION_OUTSIDER
  end
  local reaction = actor.reaction or FRIENDLY_REACTION
  local friendly = reaction >= FRIENDLY_REACTION
  if friendly then
    flags = flags + F.REACTION_FRIENDLY
  elseif reaction <= HOSTILE_REACTION then
    flags = flags + F.REACTION_HOSTILE
  else
    flags = flags + F.REACTION_NEUTRAL
  end
  local playerControlled = PLAYER_KINDS[actor.kind] or (actor.kind == "pet" and friendly)
  flags = flags + (playerControlled and F.CONTROL_PLAYER or F.CONTROL_NPC) + TYPE_OF_KIND[actor.kind]
  if byToken.target == actor then
    flags = flags + F.TARGET
  end
  if byToken.focus == actor then
    flags = flags + F.FOCUS
  end
  return flags, actor.raidTarget and 2 ^ (actor.raidTarget - 1) or 0
end

-- The GUID, Name, Flags and RaidFlags of the actor in a base role, keyed by the field name's tail.
local function roleOf(w, actor, absent)
  if not actor then
    return absent
  end
  local flags, raidFlags = M.flags(w, actor)
  return { GUID = actor.guid, Name = actor.name, Flags = flags, RaidFlags = raidFlags }
end

local function checkParams(subevent, names, params)
  local valid = { caster = true }
  for _, name in ipairs(names) do
    valid[name] = true
  end
  for key in pairs(params) do
    if not valid[key] then
      error(string.format("Log.emit: unknown field '%s' for %s; valid: %s", tostring(key), subevent, table.concat(names, ", ")), 3)
    end
  end
end

-- The value of field name when params gives none. values holds the fields packed so far (the ids come before their
-- names and schools).
local function default(w, name, subevent, values, roles)
  if name == "timestamp" then
    return M.timestamp(w)
  elseif name == "subevent" then
    return subevent
  elseif name == "hideCaster" then
    return false
  end
  local role, part = name:match("^(%l+)(%u.*)$")
  if roles[role] then
    return roles[role][part]
  end
  if name:find("[sS]pellID$") then
    error(string.format("Log.emit: %s needs %s", subevent, name), 3)
  end
  local spell, tail = name:match("^(.-[sS]pell)(%u%l+)$")
  if tail == "Name" or tail == "School" then
    local info = Spells.info(w, values[spell .. "ID"])
    return tail == "Name" and info.name or info.school or PHYSICAL
  end
  if name == "school" then
    return values.spellSchool or PHYSICAL
  end
  return Layout.DEFAULTS[name]
end

-- Packs and records one subevent. src and dst are actors or nil; params is keyed by the layout's field names (spellID,
-- amount, overkill, missType, auraType, extraSpellID, ...), plus caster (an actor) for SPELL_ABSORBED. spellName and
-- spellSchool (and the extra and absorb spell's) default from the spell data. Returns the entry: entry[1..entry.n] is the
-- payload, entry.seq its number.
function M.emit(w, subevent, src, dst, params)
  params = params or {}
  local log = w.combat.log
  local names = Layout.fields(Layout.of(w.flavor), subevent, params.spellID ~= nil)
  checkParams(subevent, names, params)
  local roles = { source = roleOf(w, src, NO_SOURCE), dest = roleOf(w, dst, NO_DEST), caster = roleOf(w, params.caster, NO_DEST) }
  local values, entry = {}, { n = #names }
  for i, name in ipairs(names) do
    local value = params[name]
    if value == nil then
      value = default(w, name, subevent, values, roles)
    end
    values[name], entry[i] = value, value
  end
  log.seq = log.seq + 1
  entry.seq = log.seq
  log.entries[#log.entries + 1] = entry
  if #log.entries > RING then
    table.remove(log.entries, 1)
  end
  local previous = log.current
  log.current = entry
  local ok, err = pcall(w.run, w, ENGINE, w.fire, w, EVENT)
  log.current = previous
  if not ok then
    error(err, 0)
  end
  return entry
end

-- source: assumed (row C18's page) outside a dispatch the accessor returns nothing.
local function currentEventInfo(w)
  return function()
    local entry = w.combat.log.current
    if entry then
      return unpack(entry, 1, entry.n)
    end
  end
end

-- Adds w.combat.log and the accessors. source: confirmed (row C18) C_CombatLog.GetCurrentEventInfo is in the api data of
-- vanilla, mists and tbc, and the bare name is Blizzard's deprecated alias there; retail and forever have neither, so
-- addons there get no payload. Installs the COMBATLOG_OBJECT_* globals where nothing defines them (row C5).
function M.install(w)
  w.combat.log = { entries = {}, seq = 0 }
  local accessor = currentEventInfo(w)
  State.define(w, "C_CombatLog.GetCurrentEventInfo", accessor)
  State.define(w, "CombatLogGetCurrentEventInfo", accessor, { "vanilla", "mists", "tbc" })
  for key, value in pairs(F) do
    local name = "COMBATLOG_OBJECT_" .. key
    if rawget(_G, name) == nil then
      w:set(name, value)
    end
  end
end

return M
