-- Kit-authored data for the combat presets (R4: every number a preset uses is here, none is a server formula): role mixes,
-- classes and races per flavor, default levels, member and enemy stats with their behaviour rules, and the spells those rules
-- cast. The lists are the kit's own picks, not read from a client; a flavor's class and race list is what the preset may
-- draw from, with no faction or race-class restriction modelled.
local M = {}

local unpack = unpack

-- source: assumed (kit data) a level per flavor; the plan's numbers.
M.LEVELS = { retail = 90, mists = 90, tbc = 70, vanilla = 60, forever = 60 }

M.SIZES = { 10, 20, 25, 40 }
M.ROLES = { "TANK", "HEALER", "DAMAGER" }
-- Members per role, the player included, for a dungeon party and each raid size.
M.ROLE_MIX = {
  dungeon = { TANK = 1, HEALER = 1, DAMAGER = 3 },
  [10] = { TANK = 2, HEALER = 2, DAMAGER = 6 },
  [20] = { TANK = 2, HEALER = 4, DAMAGER = 14 },
  [25] = { TANK = 2, HEALER = 5, DAMAGER = 18 },
  [40] = { TANK = 4, HEALER = 8, DAMAGER = 28 },
}

M.CLASS_NAMES = {
  WARRIOR = "Warrior",
  PALADIN = "Paladin",
  HUNTER = "Hunter",
  ROGUE = "Rogue",
  PRIEST = "Priest",
  DEATHKNIGHT = "Death Knight",
  SHAMAN = "Shaman",
  MAGE = "Mage",
  WARLOCK = "Warlock",
  MONK = "Monk",
  DRUID = "Druid",
  DEMONHUNTER = "Demon Hunter",
  EVOKER = "Evoker",
}

local ERA_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local MISTS_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID" }
local RETAIL_CLASSES = {
  "WARRIOR",
  "PALADIN",
  "HUNTER",
  "ROGUE",
  "PRIEST",
  "DEATHKNIGHT",
  "SHAMAN",
  "MAGE",
  "WARLOCK",
  "MONK",
  "DRUID",
  "DEMONHUNTER",
  "EVOKER",
}

-- source: assumed (kit data) no DEATHKNIGHT before the flavor that has it, no MONK before Mists, no DEMONHUNTER or
-- EVOKER outside retail; "forever" draws from the era list.
M.CLASSES = {
  retail = RETAIL_CLASSES,
  mists = MISTS_CLASSES,
  tbc = ERA_CLASSES,
  vanilla = ERA_CLASSES,
  forever = ERA_CLASSES,
}

-- The classes each role draws from, in the order members cycle through them (a flavor keeps those it has).
M.ROLE_CLASSES = {
  TANK = { "WARRIOR", "PALADIN", "DRUID", "DEATHKNIGHT", "MONK", "DEMONHUNTER" },
  HEALER = { "PRIEST", "PALADIN", "DRUID", "SHAMAN", "MONK", "EVOKER" },
  DAMAGER = { "MAGE", "ROGUE", "HUNTER", "WARLOCK", "WARRIOR", "SHAMAN", "PRIEST", "DEATHKNIGHT", "DEMONHUNTER", "EVOKER" },
}

local function race(name, file)
  return { name = name, file = file or name }
end

local ERA_ALLIANCE = { race("Human"), race("Dwarf"), race("Night Elf", "NightElf"), race("Gnome") }
local ERA_HORDE = { race("Orc"), race("Undead", "Scourge"), race("Tauren"), race("Troll") }
local function with(list, ...)
  local out = { unpack(list) }
  for _, entry in ipairs({ ... }) do
    out[#out + 1] = entry
  end
  return out
end

local TBC_ALLIANCE = with(ERA_ALLIANCE, race("Draenei"))
local TBC_HORDE = with(ERA_HORDE, race("Blood Elf", "BloodElf"))
local MISTS_ALLIANCE = with(TBC_ALLIANCE, race("Worgen"), race("Pandaren"))
local MISTS_HORDE = with(TBC_HORDE, race("Goblin"), race("Pandaren"))

-- source: assumed (kit data) the playable races per faction and flavor, listed by the flavor's expansion.
M.RACES = {
  retail = {
    Alliance = with(
      MISTS_ALLIANCE,
      race("Void Elf", "VoidElf"),
      race("Lightforged Draenei", "LightforgedDraenei"),
      race("Dark Iron Dwarf", "DarkIronDwarf"),
      race("Kul Tiran", "KulTiran"),
      race("Mechagnome"),
      race("Dracthyr")
    ),
    Horde = with(
      MISTS_HORDE,
      race("Nightborne"),
      race("Highmountain Tauren", "HighmountainTauren"),
      race("Mag'har Orc", "MagharOrc"),
      race("Zandalari Troll", "ZandalariTroll"),
      race("Vulpera"),
      race("Dracthyr")
    ),
  },
  mists = { Alliance = MISTS_ALLIANCE, Horde = MISTS_HORDE },
  tbc = { Alliance = TBC_ALLIANCE, Horde = TBC_HORDE },
  vanilla = { Alliance = ERA_ALLIANCE, Horde = ERA_HORDE },
  forever = { Alliance = ERA_ALLIANCE, Horde = ERA_HORDE },
}

-- Kit-authored spell records for the preset rules (written into w.mock.spells without replacing a scenario's own).
M.SPELL = { HEAL = 910001, BOLT = 910002 }
M.SPELLS = {
  [M.SPELL.HEAL] = { name = "Kit Preset Mend", school = 2 },
  [M.SPELL.BOLT] = { name = "Kit Preset Bolt", school = 4 },
}

-- Health, threat modifier and behaviour rules per role of a party or raid member.
M.MEMBERS = {
  TANK = { health = 1500, threatMod = 3, ai = { role = "tank", swing = { every = 2, damage = 20 } } },
  HEALER = {
    health = 900,
    ai = { role = "healer", spells = { { spellID = M.SPELL.HEAL, every = 3, castTime = 1.5, heal = 100 } } },
  },
  DAMAGER = { health = 1000, ai = { role = "dps", swing = { every = 2, damage = 35 } } },
}

local function boss(name, health, x, y)
  return {
    name = name,
    token = "boss1",
    health = health,
    pos = { x = x, y = y },
    ai = {
      targets = "threat",
      swing = { every = 2, damage = 40 },
      spells = { { spellID = M.SPELL.BOLT, every = 8, castTime = 2, damage = 150 } },
    },
  }
end

local function mob(name, health, damage, x, y)
  return { name = name, health = health, pos = { x = x, y = y }, ai = { targets = "threat", swing = { every = 3, damage = damage } } }
end

-- The enemies each preset spawns, at yard offsets in front of the player, in spawn order. boss1 is the main enemy of all.
M.PACKS = {
  solo = { boss("Kit Mob", 600, 0, 15) },
  dungeon = {
    mob("Kit Trash 1", 800, 15, -6, 20),
    mob("Kit Trash 2", 800, 15, -2, 22),
    mob("Kit Trash 3", 800, 15, 2, 22),
    mob("Kit Trash 4", 800, 15, 6, 20),
    boss("Kit Boss", 5000, 0, 35),
  },
  raid = {
    boss("Kit Boss", 20000, 0, 30),
    mob("Kit Add 1", 1500, 20, -8, 24),
    mob("Kit Add 2", 1500, 20, 8, 24),
  },
}

return M
