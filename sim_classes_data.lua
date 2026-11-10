-- The kit literals (spec 7.4): the Warrior and Mage spell records per flavor group, in action-bar order, and the Warrior's
-- proc rule. Each record is the normalized record of spec 7.1; a client extract's numbers replace the literal's, the effects
-- stay the literal's (retail damage reads base 0, Charge has no motion effect, mana costs are percentages). Every number
-- is `source: assumed` unless a line says retail 70688 (tools/run51.py --script tests/sim/proof_spells.lua) confirms it;
-- tbc 70577 has no spell tables, so every classic number is assumed. Icons are retail 70688 SpellMisc file ids (confirmed
-- for every id the retail extract holds); Heroic Strike (78) and Blizzard (10) have no retail row, so theirs are assumed.
local M = {}

-- source: confirmed (retail 70688 Charge: minRange 8, maxRange 25, no GCD, energize 200 tenths = 20 rage, 8-25 yd); assumed
-- (the stun, its 1 s, the 20 s cooldown: Charge's retail cooldown row reads 1500).
local CHARGE = {
  id = 100,
  name = "Charge",
  icon = 132337,
  school = 1,
  castTime = 0,
  cooldown = 20000,
  gcd = 0,
  duration = 1000,
  minRange = 8,
  maxRange = 25,
  effects = {
    { type = "charge", base = 0, target = "enemy" },
    { type = "energize", base = 20, target = "caster" },
    { type = "aura", aura = "stun", base = 0, target = "enemy" },
  },
}

-- source: confirmed (retail 70688 Thunder Clap: physical, instant, cooldown 6000, GCD 1500, RAGE 20, around the caster);
-- assumed (damage 10 and radius 8).
local THUNDER_CLAP = {
  id = 6343,
  name = "Thunder Clap",
  icon = 136105,
  school = 1,
  castTime = 0,
  cooldown = 6000,
  gcd = 1500,
  minRange = 0,
  maxRange = 0,
  cost = { type = "RAGE", amount = 20 },
  effects = { { type = "damage", base = 10, target = "areaSource", radius = 8 } },
}

-- source: confirmed (retail 70688 Slam: instant, GCD 1500, maxRange 5, RAGE 20); assumed (damage 25).
local SLAM = {
  id = 1464,
  name = "Slam",
  icon = 132340,
  school = 1,
  castTime = 0,
  cooldown = 0,
  gcd = 1500,
  minRange = 0,
  maxRange = 5,
  cost = { type = "RAGE", amount = 20 },
  effects = { { type = "damage", base = 25, target = "enemy" } },
}

-- source: confirmed (retail 70688 Revenge: instant, GCD 1500, RAGE 20, effect radius 8; its ImplicitTarget 104 is a cone
-- of enemies in front); assumed (the cone is the whole circle around the caster, damage 15).
local REVENGE = {
  id = 6572,
  name = "Revenge",
  icon = 132353,
  school = 1,
  castTime = 0,
  cooldown = 0,
  gcd = 1500,
  minRange = 0,
  maxRange = 5,
  cost = { type = "RAGE", amount = 20 },
  effects = { { type = "damage", base = 15, target = "areaSource", radius = 8 } },
}

-- source: assumed (classic numbers: no tbc spell table) the next-swing strike is an instant melee strike for 15 rage.
local HEROIC_STRIKE = {
  id = 78,
  name = "Heroic Strike",
  icon = 132282,
  school = 1,
  castTime = 0,
  cooldown = 0,
  gcd = 0,
  minRange = 0,
  maxRange = 5,
  cost = { type = "RAGE", amount = 15 },
  effects = { { type = "damage", base = 11, target = "enemy" } },
}

-- source: assumed (classic numbers) a 5 rage melee strike on a 5 s cooldown; retail 70688 confirms the id, the physical
-- school, the GCD 1500 and the range 5.
local OVERPOWER = {
  id = 7384,
  name = "Overpower",
  icon = 132223,
  school = 1,
  castTime = 0,
  cooldown = 5000,
  gcd = 1500,
  minRange = 0,
  maxRange = 5,
  cost = { type = "RAGE", amount = 5 },
  effects = { { type = "damage", base = 5, target = "enemy" } },
}

-- source: confirmed (retail 70688 Fireball: fire, GCD 1500, castTime 1750, range 40); assumed (mana 30, damage 20, and the
-- classic cast time 2500).
local function fireball(castTime)
  return {
    id = 133,
    name = "Fireball",
    icon = 135812,
    school = 4,
    castTime = castTime,
    cooldown = 0,
    gcd = 1500,
    minRange = 0,
    maxRange = 40,
    cost = { type = "MANA", amount = 30 },
    effects = { { type = "damage", base = 20, target = "enemy" } },
  }
end

-- source: confirmed (retail 70688 Frost Nova: frost, instant, GCD 1500, 6 s); assumed (mana 25, 25 s cooldown, damage 5,
-- radius 8, and the root aura: retail's aura 455 root is mapped in sim_spell_data).
local FROST_NOVA = {
  id = 122,
  name = "Frost Nova",
  icon = 135848,
  school = 16,
  castTime = 0,
  cooldown = 25000,
  gcd = 1500,
  duration = 6000,
  minRange = 0,
  maxRange = 0,
  cost = { type = "MANA", amount = 25 },
  effects = {
    { type = "aura", aura = "root", base = 0, target = "areaSource", radius = 8 },
    { type = "damage", base = 5, target = "areaSource", radius = 8 },
  },
}

-- source: confirmed (retail 70688 Blizzard 190356: frost, cast 2000, cooldown 12000, GCD 1500, 12 s, range 40); assumed
-- (mana 50, 8 damage a second in an 8 yd circle).
local BLIZZARD_MODERN = {
  id = 190356,
  name = "Blizzard",
  icon = 135857,
  school = 16,
  castTime = 2000,
  cooldown = 12000,
  gcd = 1500,
  duration = 12000,
  minRange = 0,
  maxRange = 40,
  cost = { type = "MANA", amount = 50 },
  effects = { { type = "persistent", aura = "periodic", base = 8, target = "areaDest", radius = 8, period = 1000 } },
}

-- source: assumed (classic numbers: no tbc spell table) the channel is an instant ground cast of 8 s, range 30.
local BLIZZARD_CLASSIC = {
  id = 10,
  name = "Blizzard",
  icon = 135857,
  school = 16,
  castTime = 0,
  cooldown = 0,
  gcd = 1500,
  duration = 8000,
  minRange = 0,
  maxRange = 30,
  cost = { type = "MANA", amount = 50 },
  effects = { { type = "persistent", aura = "periodic", base = 8, target = "areaDest", radius = 8, period = 1000 } },
}

-- class -> group -> records in action-bar order (slot 1 first).
M.KITS = {
  WARRIOR = {
    modern = { CHARGE, THUNDER_CLAP, SLAM, REVENGE },
    classic = { CHARGE, THUNDER_CLAP, HEROIC_STRIKE, OVERPOWER },
  },
  MAGE = {
    modern = { fireball(1750), FROST_NOVA, BLIZZARD_MODERN },
    classic = { fireball(2500), FROST_NOVA, BLIZZARD_CLASSIC },
  },
}

-- source: assumed (spec 7.4; Task 5.5 rules) class -> group -> the proc rules of SimProcs. The modern Warrior's Revenge! (aura
-- 5302) comes after every fourth landed swing; retail 70688 gives the aura 6 s, the rule keeps the plan's 15 s. The classic
-- Warrior's Overpower glows for 5 s after a dodged swing, with no aura.
M.PROCS = {
  WARRIOR = {
    modern = { { id = "revenge", onEvent = "swing_hit", every = 4, aura = 5302, overlay = 6572, duration = 15000 } },
    classic = { { id = "overpower", onEvent = "dodge", every = 1, overlay = 7384, duration = 5000 } },
  },
  MAGE = { modern = {}, classic = {} },
}

return M
