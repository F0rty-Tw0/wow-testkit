-- The classic paper doll's stat getters (Blizzard_CharacterFrame <flavor>/PaperDollFrame.lua). The kit models no gear,
-- so every answer is a gearless character's; the shapes are the call sites', the values assumed (row G45).
local A = require("assert")
local G = require("tests.helpers.game")

local FLAVORS = { "tbc", "vanilla" }
-- A world with no unit fixture answers no player level; the getters then read the flavor's level cap.
local LEVEL_CAP = { tbc = 70, vanilla = 60 }

local function playerLevel(flavor)
  local level = _G.UnitLevel("player")
  if type(level) == "number" and level > 0 then
    return level
  end
  return LEVEL_CAP[flavor]
end

local function numbers(values, count, label)
  for i = 1, count do
    A.eq(type(values[i]), "number", label .. " return " .. i)
  end
end

-- tbc paperdollframe.lua:346-357 concatenated UnitStat's nil effectiveStat and stopped the character window's OnShow.
local function test_unit_stat_is_a_gearless_level_based_stat_assumed()
  for _, flavor in ipairs(FLAVORS) do
    G.withGame(flavor, function()
      local level = playerLevel(flavor)
      A.same({ _G.UnitStat("player", 1) }, { 20 + level, 20 + level, 0, 0 }, flavor)
    end)
  end
end

-- tbc paperdollframe.lua:540-1125 do arithmetic on every return of these and divide by the speeds and percents.
local function test_combat_getters_answer_numbers_in_the_sheet_shape_assumed()
  for _, flavor in ipairs(FLAVORS) do
    G.withGame(flavor, function()
      local skill = playerLevel(flavor) * 5
      numbers({ _G.UnitArmor("player") }, 5, flavor .. " UnitArmor")
      A.same({ _G.UnitDefense("player") }, { skill, 0 }, flavor)
      A.same({ _G.UnitAttackBothHands("player") }, { skill, 0, skill, 0 }, flavor)
      A.same({ _G.UnitRangedAttack("player") }, { skill, 0 }, flavor)
      numbers({ _G.UnitAttackPower("player") }, 3, flavor .. " UnitAttackPower")
      numbers({ _G.UnitRangedAttackPower("player") }, 3, flavor .. " UnitRangedAttackPower")
      local speed, offhandSpeed = _G.UnitAttackSpeed("player")
      A.same({ speed > 0, offhandSpeed }, { true, nil }, flavor)
      local damage = { _G.UnitDamage("player") }
      numbers(damage, 7, flavor .. " UnitDamage")
      A.same({ damage[1] >= 1, damage[2] >= damage[1], damage[7] }, { true, true, 1 }, flavor)
      local ranged = { _G.UnitRangedDamage("player") }
      numbers(ranged, 6, flavor .. " UnitRangedDamage")
      A.same({ ranged[1] > 0, ranged[2] >= 1, ranged[6] }, { true, true, 1 }, flavor)
      A.eq(_G.HasWandEquipped(), false, flavor)
      A.eq(type(_G.UnitHasRelicSlot("player")), "boolean", flavor)
    end)
  end
end

-- tbc paperdollframe.lua:385-470, :578-608, :1004-1092 format each of these with %d / %.2f or add them.
local function test_rating_and_chance_getters_answer_zero_assumed()
  G.withGame("tbc", function()
    local answers = {
      _G.GetCombatRating(1), _G.GetCombatRatingBonus(1), _G.GetArmorPenetration(), _G.GetSpellPenetration(),
      _G.GetCritChance(), _G.GetRangedCritChance(), _G.GetSpellCritChance(2), _G.GetSpellBonusDamage(2),
      _G.GetSpellBonusHealing(), _G.GetDodgeChance(), _G.GetParryChance(), _G.GetBlockChance(), _G.GetShieldBlock(),
      _G.GetAttackPowerForStat(1, 20), _G.GetCritChanceFromAgility("player"),
      _G.GetSpellCritChanceFromIntellect("player"), _G.GetUnitHealthRegenRateFromSpirit("player"),
      _G.GetUnitManaRegenRateFromSpirit("player"),
    }
    A.same(answers, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
    A.same({ _G.GetManaRegen() }, { 0, 0 })
  end)
end

-- (G48) forever's camelot sheet adds GetOffhandHitModifier() to a rating bonus (paperdollframestats.lua:525); the
-- extract documents it, api/forever lacks it. tbc's sheet never calls it, so tbc stays without.
local function test_forever_offhand_hit_modifier_is_zero_assumed()
  G.withGame("forever", function()
    A.eq(_G.GetOffhandHitModifier(), 0)
  end)
  G.withGame("tbc", function()
    A.eq(rawget(_G, "GetOffhandHitModifier"), nil)
  end)
end

return function()
  test_forever_offhand_hit_modifier_is_zero_assumed()
  test_unit_stat_is_a_gearless_level_based_stat_assumed()
  test_combat_getters_answer_numbers_in_the_sheet_shape_assumed()
  test_rating_and_chance_getters_answer_zero_assumed()
end
