-- Payload layouts of the combat log: the field names after the timestamp of each subevent, and the COMBATLOG_OBJECT_*
-- bit values. Data only; combat_log.lua packs the values. A subevent is a prefix and a suffix (SPELL_DAMAGE), or one of
-- the special subevents.
local M = {}

local Flavors = require("tools.flavors")

local unpack = unpack

-- source: confirmed (row C1) the eleven base fields, in this order.
local BASE = {
  "timestamp",
  "subevent",
  "hideCaster",
  "sourceGUID",
  "sourceName",
  "sourceFlags",
  "sourceRaidFlags",
  "destGUID",
  "destName",
  "destFlags",
  "destRaidFlags",
}

local SPELL = { "spellID", "spellName", "spellSchool" }
local EXTRA = { "extraSpellID", "extraSpellName", "extraSpellSchool" }

-- source: confirmed (row C2) retail's parser; assumed on the other four flavors (rows C2, C3). The longest prefix is
-- tried first.
local PREFIX_ORDER = {
  "SPELL_PERIODIC",
  "SPELL_BUILDING",
  "DAMAGE_SHIELD",
  "DAMAGE_SPLIT",
  "ENVIRONMENTAL",
  "SPELL",
  "RANGE",
  "SWING",
}
local PREFIX = {
  SWING = {},
  SPELL = SPELL,
  SPELL_PERIODIC = SPELL,
  SPELL_BUILDING = SPELL,
  RANGE = SPELL,
  DAMAGE_SHIELD = SPELL,
  DAMAGE_SPLIT = SPELL,
  ENVIRONMENTAL = { "environmentalType" },
}
-- DAMAGE_SHIELD and DAMAGE_SPLIT carry the damage suffix without naming it.
local IMPLIED_SUFFIX = { DAMAGE_SHIELD = "DAMAGE", DAMAGE_SPLIT = "DAMAGE" }

local DAMAGE = { "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing", "isOffHand" }
-- source: confirmed (row C3) retail's parser, except SPELL_ABSORBED (the wiki alone); assumed on the other flavors. The
-- aura second value is Blizzard's remainingPoints (the wiki's amount) and _CAST_FAILED has one field.
local SUFFIX = {
  DAMAGE = DAMAGE,
  MISSED = { "missType", "isOffHand", "amountMissed", "critical" },
  HEAL = { "amount", "overhealing", "absorbed", "critical" },
  AURA_APPLIED = { "auraType", "remainingPoints" },
  AURA_REMOVED = { "auraType", "remainingPoints" },
  AURA_REFRESH = { "auraType", "remainingPoints" },
  AURA_APPLIED_DOSE = { "auraType", "amount" },
  AURA_REMOVED_DOSE = { "auraType", "amount" },
  CAST_FAILED = { "failedType" },
  CAST_START = {},
  CAST_SUCCESS = {},
  INTERRUPT = EXTRA,
  DISPEL = { "extraSpellID", "extraSpellName", "extraSpellSchool", "auraType" },
  RESURRECT = {},
  ABSORBED = {
    "casterGUID",
    "casterName",
    "casterFlags",
    "casterRaidFlags",
    "absorbSpellID",
    "absorbSpellName",
    "absorbSpellSchool",
    "amount",
    "critical",
  },
}
-- source: confirmed (row C3) ENVIRONMENTAL_DAMAGE has the damage list without isOffHand.
local SUFFIX_OF_PREFIX = { ENVIRONMENTAL = { DAMAGE = { unpack(DAMAGE, 1, #DAMAGE - 1) } } }
-- The attack spell fields of SPELL_ABSORBED are there only when a spell dealt the absorbed damage.
local OPTIONAL_PREFIX = { ABSORBED = true }

-- source: confirmed (rows C3, C4) UNIT_DIED carries recapID and unconsciousOnDeath after the base fields.
local SPECIAL = {
  UNIT_DIED = { "recapID", "unconsciousOnDeath" },
  UNIT_DESTROYED = { "recapID", "unconsciousOnDeath" },
  UNIT_DISSIPATES = {},
  PARTY_KILL = {},
}

-- source: confirmed (row C4) values a field takes when the scenario gives none; assumed (row C4) the numbers and
-- false: Blizzard compares overkill with > 0, so it is always a number.
M.DEFAULTS = { overkill = 0, overhealing = 0, isOffHand = false, recapID = 0, unconsciousOnDeath = false }

local LAYOUT = { base = BASE, prefix = PREFIX, suffix = SUFFIX, special = SPECIAL }

-- source: assumed (row C3) the other flavors share retail's lists, so one layout serves all five.
function M.of(flavor)
  Flavors.get(flavor) -- raises for an unknown flavor
  return LAYOUT
end

-- The prefix and suffix names of subevent, nil when it is not one (specials return nil, nil).
local function split(layout, subevent)
  for _, prefix in ipairs(PREFIX_ORDER) do
    if subevent == prefix and IMPLIED_SUFFIX[prefix] then
      return prefix, IMPLIED_SUFFIX[prefix]
    end
    if subevent:sub(1, #prefix + 1) == prefix .. "_" and layout.suffix[subevent:sub(#prefix + 2)] then
      return prefix, subevent:sub(#prefix + 2)
    end
  end
end

-- Every field name of subevent in payload order, the base included. withAttack says a SPELL_ABSORBED event names the
-- spell that dealt the damage. Raises for a subevent the layout does not hold.
function M.fields(layout, subevent, withAttack)
  local names = {}
  local function append(list)
    for _, name in ipairs(list) do
      names[#names + 1] = name
    end
  end
  append(layout.base)
  if layout.special[subevent] then
    append(layout.special[subevent])
    return names
  end
  local prefix, suffix = split(layout, subevent)
  if not prefix then
    error(string.format("Log.emit: unknown subevent '%s'", tostring(subevent)), 3)
  end
  if withAttack or not OPTIONAL_PREFIX[suffix] then
    append(layout.prefix[prefix])
  end
  append((SUFFIX_OF_PREFIX[prefix] or {})[suffix] or layout.suffix[suffix])
  return names
end

-- source: confirmed (row C5) the COMBATLOG_OBJECT_* values, from CombatLogConstants.lua; the global names follow
-- deprecated_combatlog.lua.
M.FLAGS = {
  AFFILIATION_MINE = 0x1,
  AFFILIATION_PARTY = 0x2,
  AFFILIATION_RAID = 0x4,
  AFFILIATION_OUTSIDER = 0x8,
  AFFILIATION_MASK = 0xF,
  REACTION_FRIENDLY = 0x10,
  REACTION_NEUTRAL = 0x20,
  REACTION_HOSTILE = 0x40,
  REACTION_MASK = 0xF0,
  CONTROL_PLAYER = 0x100,
  CONTROL_NPC = 0x200,
  CONTROL_MASK = 0x300,
  TYPE_PLAYER = 0x400,
  TYPE_NPC = 0x800,
  TYPE_PET = 0x1000,
  TYPE_GUARDIAN = 0x2000,
  TYPE_OBJECT = 0x4000,
  TYPE_MASK = 0xFC00,
  TARGET = 0x10000,
  FOCUS = 0x20000,
  MAINTANK = 0x40000,
  MAINASSIST = 0x80000,
  NONE = 0x80000000,
  SPECIAL_MASK = 0xFFFF0000,
  RAID_TARGET_MASK = 0xFF,
  RAID_MASK = 0xFFFFFFFF,
}
for i = 1, 8 do
  M.FLAGS["RAIDTARGET" .. i] = 2 ^ (i - 1)
end

return M
