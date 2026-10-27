-- Combat log layouts: the field names after the timestamp for each subevent, on every flavor.
local A = require("assert")
local Flavors = require("tools.flavors")
local Layout = require("combat_log_layout")

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

-- The names after the base.
local function after(subevent, withAttack)
  local layout = Layout.of("retail")
  local names = Layout.fields(layout, subevent, withAttack)
  return { unpack(names, #BASE + 1) }
end

local function test_layout_base_is_identical_on_all_flavours() -- (C1)
  for _, flavor in ipairs(Flavors.list) do
    A.same(Layout.of(flavor).base, BASE)
  end
end

local function test_swing_has_no_spell_prefix() -- (C2)
  A.same(
    after("SWING_DAMAGE"),
    { "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing", "isOffHand" }
  )
end

local function test_spell_and_range_and_periodic_share_the_spell_prefix() -- (C2)
  for _, subevent in ipairs({ "SPELL_HEAL", "SPELL_PERIODIC_HEAL", "RANGE_HEAL" }) do
    A.same(after(subevent), { "spellID", "spellName", "spellSchool", "amount", "overhealing", "absorbed", "critical" })
  end
end

local function test_environmental_damage_has_no_off_hand() -- (C2, C3)
  A.same(
    after("ENVIRONMENTAL_DAMAGE"),
    { "environmentalType", "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing" }
  )
end

local function test_damage_shield_carries_the_spell_and_the_damage_suffix() -- (C2)
  A.same({ unpack(after("DAMAGE_SHIELD"), 1, 4) }, { "spellID", "spellName", "spellSchool", "amount" })
  A.same(after("DAMAGE_SPLIT"), after("DAMAGE_SHIELD"))
  A.same({ unpack(after("DAMAGE_SHIELD_MISSED"), 4, 4) }, { "missType" })
end

local function test_aura_and_dose_suffixes() -- (C3)
  A.same({ unpack(after("SPELL_AURA_APPLIED"), 4) }, { "auraType", "remainingPoints" })
  A.same({ unpack(after("SPELL_AURA_REMOVED_DOSE"), 4) }, { "auraType", "amount" })
  A.same({ unpack(after("SPELL_CAST_FAILED"), 4) }, { "failedType" })
end

local function test_interrupt_and_dispel_extra_spell() -- (C3)
  A.same({ unpack(after("SPELL_INTERRUPT"), 4) }, { "extraSpellID", "extraSpellName", "extraSpellSchool" })
  A.same({ unpack(after("SPELL_DISPEL"), 4) }, { "extraSpellID", "extraSpellName", "extraSpellSchool", "auraType" })
end

local function test_unit_died_carries_the_recap() -- (C3)
  A.same(after("UNIT_DIED"), { "recapID", "unconsciousOnDeath" })
end

local function test_spell_absorbed_has_the_attack_spell_only_when_a_spell_attacked() -- (C3)
  local tail =
    { "casterGUID", "casterName", "casterFlags", "casterRaidFlags", "absorbSpellID", "absorbSpellName", "absorbSpellSchool", "amount", "critical" }
  A.same(after("SPELL_ABSORBED"), tail)
  A.same({ unpack(after("SPELL_ABSORBED", true), 1, 3) }, { "spellID", "spellName", "spellSchool" })
  A.same({ unpack(after("SPELL_ABSORBED", true), 4) }, tail)
end

local function test_an_unknown_subevent_raises()
  A.errors(function()
    Layout.fields(Layout.of("retail"), "SPELL_NONSENSE")
  end, "unknown subevent 'SPELL_NONSENSE'")
  A.errors(function()
    Layout.of("cataclysm")
  end, "unknown flavor")
end

local function test_flag_values() -- (C5)
  local F = Layout.FLAGS
  A.same({ F.AFFILIATION_MINE, F.REACTION_FRIENDLY, F.CONTROL_PLAYER, F.TYPE_PLAYER }, { 0x1, 0x10, 0x100, 0x400 })
  A.same({ F.RAIDTARGET1, F.RAIDTARGET8, F.NONE, F.TYPE_MASK }, { 1, 128, 0x80000000, 0xFC00 })
end

return function()
  test_layout_base_is_identical_on_all_flavours()
  test_swing_has_no_spell_prefix()
  test_spell_and_range_and_periodic_share_the_spell_prefix()
  test_environmental_damage_has_no_off_hand()
  test_damage_shield_carries_the_spell_and_the_damage_suffix()
  test_aura_and_dose_suffixes()
  test_interrupt_and_dispel_extra_spell()
  test_unit_died_carries_the_recap()
  test_spell_absorbed_has_the_attack_spell_only_when_a_spell_attacked()
  test_an_unknown_subevent_raises()
  test_flag_values()
end
