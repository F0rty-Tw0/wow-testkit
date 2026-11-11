-- Character-sheet stat getters the classic paper doll (Blizzard_CharacterFrame <flavor>/PaperDollFrame.lua and
-- PetPaperDollFrame.lua) reads on every show. The flavors' globals list them with no API doc, so the plain stub
-- answered nil and the sheet's arithmetic and concatenation raised. The kit models no gear, auras or talents: every
-- answer is a gearless character's, from the level and class the kit already answers.
local M = {}

local Roster = require("combat_roster_data")
local State = require("game.state")
local define = State.define

M.DEFAULTS = {}

-- source: assumed (row G45) a gearless primary stat: 20 plus the unit's level.
local STAT_BASE = 20
-- source: assumed (row G45) weapon and defense skill are 5 per level, the cap of a character with no skill bonus.
local SKILL_PER_LEVEL = 5
-- source: assumed (row G45) a 2.0 s main-hand swing (an unarmed character's) and a 1-2 damage hit, so no caller divides
-- by zero and the sheet's max(floor(min), 1) floors hold.
local SWING_SPEED = 2.0
local MIN_DAMAGE, MAX_DAMAGE = 1, 2
-- source: assumed (row G45) the classes whose ranged slot is a relic slot (libram, idol, totem).
local RELIC_CLASSES = { PALADIN = true, DRUID = true, SHAMAN = true }

-- source: confirmed (row G45) each answers one number the sheet formats, compares or adds (tbc paperdollframe.lua
-- :437-438, :445, :455, :458, :578-595, :1004, :1041, :1051, :1061, :1070, :385, :401, :409, :422, :424); assumed 0:
-- no gear, ratings or auras add any.
local ZERO_GETTERS = {
  "GetCombatRating",
  "GetCombatRatingBonus",
  "GetArmorPenetration",
  "GetSpellPenetration",
  "GetCritChance",
  "GetRangedCritChance",
  "GetSpellCritChance",
  "GetSpellBonusDamage",
  "GetSpellBonusHealing",
  "GetDodgeChance",
  "GetParryChance",
  "GetBlockChance",
  "GetShieldBlock",
  "GetAttackPowerForStat",
  "GetCritChanceFromAgility",
  "GetSpellCritChanceFromIntellect",
  "GetUnitHealthRegenRateFromSpirit",
  "GetUnitManaRegenRateFromSpirit",
}

local function zero()
  return 0
end

function M.install(w)
  -- source: assumed (row G45) a unit with no level (no fixture, no pet) reads as the flavor's level cap, the level the
  -- kit's roster presets use.
  local function level(unit)
    local answer = _G.UnitLevel(unit)
    if type(answer) == "number" and answer > 0 then
      return answer
    end
    return Roster.LEVELS[w.flavor]
  end
  local function skill(unit)
    return level(unit) * SKILL_PER_LEVEL
  end

  for _, name in ipairs(ZERO_GETTERS) do
    define(w, name, zero)
  end
  -- source: confirmed (row G45) the returns stat, effectiveStat, posBuff, negBuff: tbc paperdollframe.lua:346-359
  -- concatenates effectiveStat and compares the buffs, petpaperdollframe.lua:135 the same for "pet".
  define(w, "UnitStat", function(unit)
    local stat = STAT_BASE + level(unit)
    return stat, stat, 0, 0
  end)
  -- source: confirmed (row G45) the returns base, effectiveArmor, armor, posBuff, negBuff: tbc paperdollframe.lua:540-545;
  -- assumed 0, as armor comes from gear.
  define(w, "UnitArmor", function()
    return 0, 0, 0, 0, 0
  end)
  -- source: confirmed (row G45) base, modifier: tbc paperdollframe.lua:561-564 and :599-601, where base equal to 5 per
  -- level gives no dodge, block or parry from defense.
  define(w, "UnitDefense", function(unit)
    return skill(unit), 0
  end)
  -- source: confirmed (row G45) mainHandBase, mainHandMod, offHandBase, offHandMod: tbc paperdollframe.lua:766-785.
  define(w, "UnitAttackBothHands", function(unit)
    local base = skill(unit)
    return base, 0, base, 0
  end)
  -- source: confirmed (row G45) rangedBase, rangedMod: tbc paperdollframe.lua:829-857.
  define(w, "UnitRangedAttack", function(unit)
    return skill(unit), 0
  end)
  -- source: confirmed (row G45) base, posBuff, negBuff: tbc paperdollframe.lua:756-759 and :983-986 add the three;
  -- assumed 0, as no gear or aura grants attack power.
  for _, name in ipairs({ "UnitAttackPower", "UnitRangedAttackPower" }) do
    define(w, name, function()
      return 0, 0, 0
    end)
  end
  -- source: confirmed (row G45) speed, offhandSpeed, where a nil offhandSpeed means no off-hand weapon: tbc
  -- paperdollframe.lua:621, :697, :733-740.
  define(w, "UnitAttackSpeed", function()
    return SWING_SPEED, nil
  end)
  -- source: confirmed (row G45) minDamage, maxDamage, minOffHand, maxOffHand, physicalBonusPos, physicalBonusNeg, percent:
  -- tbc paperdollframe.lua:629-642 divides by percent, so percent is 1.
  define(w, "UnitDamage", function()
    return MIN_DAMAGE, MAX_DAMAGE, 0, 0, 0, 0, 1
  end)
  -- source: confirmed (row G45) speed, minDamage, maxDamage, physicalBonusPos, physicalBonusNeg, percent: tbc
  -- paperdollframe.lua:887-914, :969-970.
  define(w, "UnitRangedDamage", function()
    return SWING_SPEED, MIN_DAMAGE, MAX_DAMAGE, 0, 0, 1
  end)
  -- source: confirmed (row G45) base, casting mana per second: tbc paperdollframe.lua:1092-1095 multiplies both; assumed 0.
  define(w, "GetManaRegen", function()
    return 0, 0
  end)
  -- source: confirmed (row G45) a boolean the sheet tests (tbc paperdollframe.lua:897); assumed no wand.
  define(w, "HasWandEquipped", function()
    return false
  end)
  -- source: confirmed (row G45) a boolean the sheet tests (tbc paperdollframe.lua:105, :828, :876); assumed true for the
  -- relic classes.
  define(w, "UnitHasRelicSlot", function(unit)
    local _, classFile = _G.UnitClass(unit)
    return RELIC_CLASSES[classFile] == true
  end)
end

return M
