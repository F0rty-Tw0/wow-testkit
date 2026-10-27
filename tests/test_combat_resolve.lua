-- Resolve: the one place combat changes health. Damage resolves in a fixed order, then logs, then fires unit events.
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local H = require("tests.helpers.combat")
local Resolve = require("combat_resolve")
local Threat = require("combat_threat")

-- Brute hits Ann for 100. Ann has Kit Ward (absorb 60) and a 0.5 reduction aura.
-- 100 * 0.5 = 50 after reduction; the ward takes 50 of 60 (10 left); health stays 1000.
local function test_reduction_then_absorb_then_health()
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    Auras.apply(w, ann, { spellID = H.SPELLS.WARD, absorb = 60 })
    Auras.apply(w, ann, { spellID = H.SPELLS.CURSE, reduction = 0.5 })
    local r = Resolve.damage(w, brute, ann, { amount = 100 })
    A.same({ r.dealt, r.absorbed }, { 0, 50 })
    A.eq(_G.UnitHealth("party1"), 1000)
    A.eq(_G.UnitGetTotalAbsorbs("party1"), 10)
  end)
end

local function test_immunity_logs_missed_immune_and_changes_nothing()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    Auras.apply(w, ann, { spellID = H.SPELLS.WARD, immune = true })
    local log = H.watch(w, { "UNIT_HEALTH" })
    local r = Resolve.damage(w, brute, ann, { amount = 100 })
    A.same({ r.dealt, r.missed }, { 0, "IMMUNE" })
    A.same(H.subevents(c), { "SWING_MISSED" })
    A.eq(c.log.entries[1][12], "IMMUNE")
    A.eq(#log, 0)
    A.eq(Threat.get(brute, ann), 0)
    A.eq(brute.threatList, nil)
  end)
end

local function test_damage_order_log_before_unit_events() -- (C7)
  H.withCombat("vanilla", function(w)
    local ann, brute = H.pair(w)
    local order = H.sequence(w, { "UNIT_HEALTH" })
    Resolve.damage(w, brute, ann, { amount = 100 })
    A.same(order, { "SWING_DAMAGE", "UNIT_HEALTH" })
    A.eq(ann.health, 900)
  end)
end

-- Threat and engagement are written before the log line, but their events (UNIT_THREAT_*, UNIT_FLAGS) come after it.
local function test_damage_log_before_threat_and_flags_events_assumed() -- (C7)
  H.withCombat("vanilla", function(w)
    local ann, brute = H.pair(w)
    local order = H.sequence(w, { "UNIT_THREAT_LIST_UPDATE", "UNIT_FLAGS" })
    Resolve.damage(w, ann, brute, { amount = 100 })
    A.eq(order[1], "SWING_DAMAGE")
    A.eq(#order > 1, true)
  end)
end

local function test_lethal_damage_kills_in_order()
  H.withCombat("vanilla", function(w, c)
    local ann, brute = H.pair(w)
    Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
    local order = H.sequence(w, { "UNIT_HEALTH" })
    local r = Resolve.damage(w, brute, ann, { amount = 1500 })
    A.same({ r.dealt, r.overkill }, { 1500, 500 })
    A.same(order, { "SWING_DAMAGE", "UNIT_DIED", "UNIT_HEALTH" })
    A.eq(c.log.entries[1][13], 500) -- overkill
    A.same({ _G.UnitIsDeadOrGhost("party1"), _G.UnitHealth("party1"), #ann.auras }, { true, 0, 0 })
    A.eq(c.log.entries[2][4], "0000000000000000") -- no source
  end)
end

local function test_threat_uses_the_source_modifier()
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    ann.threatMod = 3
    Resolve.damage(w, ann, brute, { amount = 100 })
    A.eq(Threat.get(brute, ann), 300)
    A.eq(ann.affectingCombat, true) -- State.engage
  end)
end

local function test_heal_caps_at_max_and_reports_overheal()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    Actors.setHealth(w, ann, 900)
    local r = Resolve.heal(w, brute, ann, { amount = 250, spellID = H.SPELLS.MEND })
    A.same({ r.healed, r.overheal, ann.health }, { 100, 150, 1000 })
    A.same(H.subevents(c), { "SPELL_HEAL" })
    A.same({ c.log.entries[1][15], c.log.entries[1][16] }, { 250, 150 }) -- amount, overhealing
  end)
end

local function test_revive_restores_health_and_clears_dead()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    Resolve.kill(w, ann)
    local log = H.watch(w, { "UNIT_HEALTH", "UNIT_FLAGS" })
    Resolve.revive(w, ann, 300)
    A.same({ ann.health, ann.isDead, _G.UnitIsDeadOrGhost("party1") }, { 300, false, false })
    A.same(H.names(log), { "UNIT_HEALTH", "UNIT_FLAGS" })
    A.same(H.subevents(c), { "UNIT_DIED" }) -- no src: no SPELL_RESURRECT
    Resolve.kill(w, ann)
    Resolve.revive(w, ann, 100, brute, H.SPELLS.MEND)
    A.same(H.subevents(c), { "UNIT_DIED", "UNIT_DIED", "SPELL_RESURRECT" })
    A.eq(c.log.entries[3][4], brute.guid)
  end)
end

local function test_miss_spec_logs_missed_with_that_type_and_changes_no_health()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    local log = H.watch(w, { "UNIT_HEALTH" })
    local r = Resolve.damage(w, brute, ann, { amount = 100, spellID = H.SPELLS.STRIKE, miss = "DODGE" })
    A.same({ r.dealt, r.missed, ann.health, #log }, { 0, "DODGE", 1000, 0 })
    A.same(H.subevents(c), { "SPELL_MISSED" })
    A.eq(c.log.entries[1][15], "DODGE")
  end)
end

local function test_absorbs_consume_in_apply_order_and_log_each()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    local first = Auras.apply(w, ann, { spellID = H.SPELLS.WARD, absorb = 30 })
    local second = Auras.apply(w, ann, { spellID = H.SPELLS.CURSE, absorb = 50 })
    local r = Resolve.damage(w, brute, ann, { amount = 100, spellID = H.SPELLS.STRIKE })
    A.same({ r.dealt, r.absorbed, ann.health }, { 20, 80, 980 })
    A.same(H.subevents(c), { "SPELL_ABSORBED", "SPELL_ABSORBED", "SPELL_DAMAGE" })
    A.same({ c.log.entries[1][12], c.log.entries[1][19], c.log.entries[1][20] }, { H.SPELLS.STRIKE, H.SPELLS.WARD, "Kit Ward" })
    A.eq(c.log.entries[2][22], 50) -- amount taken from the second ward
    A.same({ #ann.auras, ann.absorbs }, { 0, 0 }) -- both wards ran out and left
    A.eq(first.absorb + second.absorb, 0)
  end)
end

return function()
  test_reduction_then_absorb_then_health()
  test_immunity_logs_missed_immune_and_changes_nothing()
  test_damage_order_log_before_unit_events()
  test_damage_log_before_threat_and_flags_events_assumed()
  test_lethal_damage_kills_in_order()
  test_threat_uses_the_source_modifier()
  test_heal_caps_at_max_and_reports_overheal()
  test_revive_restores_health_and_clears_dead()
  test_miss_spec_logs_missed_with_that_type_and_changes_no_health()
  test_absorbs_consume_in_apply_order_and_log_each()
end
