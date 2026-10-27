-- Combat auras: instance ids, the C_UnitAuras readers, absorb totals and expiry on the world clock.
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local Combat = require("combat")
local H = require("tests.helpers.combat")

local function test_instance_ids_count_from_one_and_answer_by_index() -- (C8)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
    Auras.apply(w, ann, { spellID = H.SPELLS.CURSE })
    local C = _G.C_UnitAuras
    A.eq(C.GetAuraDataByIndex("party1", 1, "HELPFUL").auraInstanceID, 1)
    A.eq(C.GetAuraDataByAuraInstanceID("party1", 2).name, "Kit Curse")
    A.eq(C.GetAuraDataBySpellName("party1", "Kit Curse", "HARMFUL").spellId, H.SPELLS.CURSE)
    A.eq(C.GetAuraDataByIndex("party1", 2, "HELPFUL"), nil)
    A.eq(C.GetAuraDataByIndex("party1", 1, "HARMFUL").auraInstanceID, 2)
  end)
end

local function test_aura_data_carries_the_documented_fields_and_no_kit_extras() -- (C8)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    Auras.apply(w, ann, { spellID = H.SPELLS.WARD, source = brute, stacks = 3, absorb = 100, dispelName = "Magic" })
    local data = _G.C_UnitAuras.GetAuraDataByIndex("party1", 1, "HELPFUL")
    A.same(
      { data.name, data.spellId, data.applications, data.dispelName, data.isHelpful, data.isHarmful, data.sourceUnit },
      { "Kit Ward", H.SPELLS.WARD, 3, "Magic", true, false, "boss1" }
    )
    A.same({ data.absorb, data.reduction, data.immune }, {})
    data.name = "mutated" -- the addon holds a copy, not the store
    A.eq(ann.auras[1].name, "Kit Ward")
  end)
end

local function test_harmful_follows_the_spell_when_the_spec_is_silent()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local curse = Auras.apply(w, ann, { spellID = H.SPELLS.CURSE })
    local ward = Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
    local forced = Auras.apply(w, ann, { spellID = H.SPELLS.WARD, harmful = true })
    A.same({ curse.isHarmful, ward.isHarmful, forced.isHarmful, forced.isHelpful }, { true, false, true, false })
  end)
end

local function test_unknown_unit_is_unscripted_and_a_known_miss_is_not()
  H.withCombat("retail", function(w)
    H.pair(w)
    A.eq(_G.C_UnitAuras.GetAuraDataByIndex("party1", 1, "HELPFUL"), nil)
    A.eq(w.unscripted["C_UnitAuras.GetAuraDataByIndex"], nil)
    A.eq(_G.C_UnitAuras.GetAuraDataByIndex("party4", 1, "HELPFUL"), nil)
    A.eq(w.unscripted["C_UnitAuras.GetAuraDataByIndex"], 1)
  end)
end

local function test_total_absorbs_sums_absorb_auras()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    A.eq(_G.UnitGetTotalAbsorbs("party1"), 0)
    local first = Auras.apply(w, ann, { spellID = H.SPELLS.WARD, absorb = 100 })
    Auras.apply(w, ann, { spellID = H.SPELLS.WARD, absorb = 200 })
    A.eq(_G.UnitGetTotalAbsorbs("party1"), 300)
    Auras.remove(w, ann, first)
    A.eq(_G.UnitGetTotalAbsorbs("party1"), 200)
    A.eq(w.unscripted.UnitGetTotalAbsorbs, nil)
  end)
end

local function test_duration_expires_on_the_world_clock_assumed() -- (C8)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local aura = Auras.apply(w, ann, { spellID = H.SPELLS.WARD, duration = 5 })
    A.same({ aura.duration, aura.expirationTime }, { 5, 1005 })
    w:advance(4)
    A.eq(#ann.auras, 1)
    w:advance(1)
    A.eq(#ann.auras, 0)
  end)
end

local function test_no_duration_never_expires_assumed() -- (C8)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local aura = Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
    A.same({ aura.duration, aura.expirationTime }, { 0, 0 })
    w:advance(100000)
    A.eq(#ann.auras, 1)
  end)
end

local function test_refresh_and_stacks_keep_the_instance_id()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local aura = Auras.apply(w, ann, { spellID = H.SPELLS.CURSE, duration = 5, stacks = 1 })
    w:advance(3)
    Auras.refresh(w, ann, aura)
    A.eq(aura.expirationTime, 1008)
    w:advance(4) -- past the first expiry, before the refreshed one
    A.eq(#ann.auras, 1)
    Auras.setStacks(w, ann, aura, 4)
    A.same({ aura.applications, aura.auraInstanceID }, { 4, 1 })
    w:advance(1)
    A.eq(#ann.auras, 0)
  end)
end

local function test_removed_aura_is_gone_once_and_its_timer_cancelled()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local aura = Auras.apply(w, ann, { spellID = H.SPELLS.CURSE, duration = 5 })
    Auras.remove(w, ann, aura)
    Auras.remove(w, ann, aura)
    A.eq(#ann.auras, 0)
    A.eq(#w.timers, 0)
  end)
end

local function test_hook_payload_names_the_changed_instance()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local updates = {}
    Combat.listen(w, "aura", function(actor, update)
      updates[#updates + 1] = { actor, update }
    end)
    local aura = Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
    Auras.setStacks(w, ann, aura, 2)
    Auras.remove(w, ann, aura)
    A.eq(updates[1][1], ann)
    A.eq(updates[1][2].addedAuras[1], aura)
    A.same(updates[2][2].updatedAuraInstanceIDs, { 1 })
    A.same(updates[3][2].removedAuraInstanceIDs, { 1 })
  end)
end

local function test_auras_follow_the_actor_across_tokens()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
    Actors.bind(w, ann, "target")
    A.eq(_G.C_UnitAuras.GetAuraDataByIndex("target", 1, "HELPFUL").name, "Kit Ward")
    A.eq(_G.C_UnitAuras.GetAuraDataByAuraInstanceID("target", 1).spellId, H.SPELLS.WARD)
  end)
end

local function test_despawn_cancels_the_expiry_timers()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Auras.apply(w, ann, { spellID = H.SPELLS.CURSE, duration = 5 })
    Actors.remove(w, ann)
    A.eq(#w.timers, 0)
  end)
end

local function test_buff_and_debuff_data_by_index_match_unit_aura()
  H.withCombat("vanilla", function(w)
    local ann = H.pair(w)
    Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
    Auras.apply(w, ann, { spellID = H.SPELLS.CURSE })
    A.eq(_G.C_UnitAuras.GetBuffDataByIndex("party1", 1).name, "Kit Ward")
    A.eq((_G.UnitBuff("party1", 1)), "Kit Ward")
    A.eq(_G.C_UnitAuras.GetDebuffDataByIndex("party1", 1, "HARMFUL").name, "Kit Curse")
    A.eq((_G.UnitDebuff("party1", 1)), "Kit Curse")
    A.eq(_G.C_UnitAuras.GetBuffDataByIndex("party1", 2), nil)
  end)
end

local function test_every_flavor_installs_the_readers()
  for _, flavor in ipairs({ "retail", "mists", "vanilla", "tbc", "forever" }) do
    H.withCombat(flavor, function(w)
      local ann = H.pair(w)
      Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
      A.eq(_G.C_UnitAuras.GetAuraDataByIndex("party1", 1, "HELPFUL").name, "Kit Ward", flavor)
    end)
  end
end

return function()
  test_instance_ids_count_from_one_and_answer_by_index()
  test_aura_data_carries_the_documented_fields_and_no_kit_extras()
  test_harmful_follows_the_spell_when_the_spec_is_silent()
  test_unknown_unit_is_unscripted_and_a_known_miss_is_not()
  test_total_absorbs_sums_absorb_auras()
  test_duration_expires_on_the_world_clock_assumed()
  test_no_duration_never_expires_assumed()
  test_refresh_and_stacks_keep_the_instance_id()
  test_removed_aura_is_gone_once_and_its_timer_cancelled()
  test_hook_payload_names_the_changed_instance()
  test_auras_follow_the_actor_across_tokens()
  test_despawn_cancels_the_expiry_timers()
  test_buff_and_debuff_data_by_index_match_unit_aura()
  test_every_flavor_installs_the_readers()
end
