-- Resolve's spell-driven actions: casts, interrupts, failures, auras, stacks and dispels, each logged before its unit events.
local A = require("assert")
local Auras = require("combat_auras")
local H = require("tests.helpers.combat")
local Resolve = require("combat_resolve_spell")

local function test_cast_with_a_cast_time_resolves_at_the_end()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    local ran = 0
    local log = H.watch(w, { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP" })
    Resolve.cast(w, brute, {
      spellID = H.SPELLS.BOLT,
      target = ann,
      effect = function()
        ran = ran + 1
      end,
    })
    A.same(H.subevents(c), { "SPELL_CAST_START" })
    A.same(H.names(log), { "UNIT_SPELLCAST_START" })
    A.eq(c.log.entries[1][8], ann.guid)
    w:advance(1)
    A.eq(ran, 0)
    w:advance(1)
    A.same(H.subevents(c), { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" })
    A.same(H.names(log), { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP" })
    A.same({ ran, brute.cast }, { 1, nil })
  end)
end

local function test_interrupt_cancels_the_pending_effect()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    local ran = false
    Resolve.cast(w, brute, {
      spellID = H.SPELLS.BOLT,
      effect = function()
        ran = true
      end,
    })
    A.eq(Resolve.interrupt(w, ann, brute, H.SPELLS.STRIKE), true)
    w:advance(5)
    A.eq(ran, false)
    A.same(H.subevents(c), { "SPELL_CAST_START", "SPELL_INTERRUPT" })
    A.eq(c.log.entries[2][15], H.SPELLS.BOLT) -- extraSpellId: the interrupted spell
    A.eq(Resolve.interrupt(w, ann, brute, H.SPELLS.STRIKE), false) -- nothing left to interrupt
  end)
end

local function test_interrupt_is_refused_for_a_cast_that_cannot_be_interrupted_assumed()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    local ran = false
    Resolve.cast(w, brute, {
      spellID = H.SPELLS.BOLT,
      notInterruptible = true,
      effect = function()
        ran = true
      end,
    })
    A.eq(Resolve.interrupt(w, ann, brute, H.SPELLS.STRIKE), false)
    w:advance(2)
    A.same({ ran, #c.log.entries }, { true, 2 })
  end)
end

local function test_an_instant_cast_logs_success_and_runs_the_effect()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    local ran = false
    Resolve.cast(w, ann, {
      spellID = H.SPELLS.STRIKE,
      target = brute,
      effect = function()
        ran = true
      end,
    })
    A.same({ H.subevents(c), ran }, { { "SPELL_CAST_SUCCESS" }, true })
  end)
end

local function test_dispel_logs_then_removes_the_aura()
  H.withCombat("vanilla", function(w, c)
    local ann, brute = H.pair(w)
    local aura = Auras.apply(w, ann, { spellID = H.SPELLS.CURSE, source = brute })
    local order = H.sequence(w, { "UNIT_AURA" })
    Resolve.dispel(w, ann, ann, aura, H.SPELLS.MEND)
    A.same(order, { "SPELL_DISPEL", "UNIT_AURA" })
    A.eq(#ann.auras, 0)
    A.same({ c.log.entries[1][15], c.log.entries[1][18] }, { H.SPELLS.CURSE, "DEBUFF" })
  end)
end

local function test_cast_failed_logs_the_failed_type()
  H.withCombat("retail", function(w, c)
    local _, brute = H.pair(w)
    Resolve.cast(w, brute, { spellID = H.SPELLS.BOLT })
    A.eq(Resolve.fail(w, brute, "Not enough mana"), true)
    A.same(H.subevents(c), { "SPELL_CAST_START", "SPELL_CAST_FAILED" })
    A.same({ c.log.entries[2][15], brute.cast }, { "Not enough mana", nil })
    A.eq(Resolve.fail(w, brute, "Not enough mana"), false) -- nothing to fail
  end)
end

local function test_stack_increase_logs_applied_dose()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    local aura = Resolve.aura(w, brute, ann, { spellID = H.SPELLS.CURSE, stacks = 1 })
    Resolve.stacks(w, ann, aura, 3)
    Resolve.stacks(w, ann, aura, 2) -- a decrease logs nothing
    A.same(H.subevents(c), { "SPELL_AURA_APPLIED", "SPELL_AURA_APPLIED_DOSE" })
    A.same({ c.log.entries[2][15], c.log.entries[2][16], aura.applications }, { "DEBUFF", 3, 2 })
  end)
end

local function test_aura_logs_applied_before_the_unit_aura_event()
  H.withCombat("vanilla", function(w, c)
    local ann, brute = H.pair(w)
    local order = H.sequence(w, { "UNIT_AURA" })
    local aura = Resolve.aura(w, brute, ann, { spellID = H.SPELLS.WARD, absorb = 40 })
    A.same(order, { "SPELL_AURA_APPLIED", "UNIT_AURA" })
    A.same({ c.log.entries[1][15], c.log.entries[1][16], aura.sourceUnit }, { "BUFF", 40, "boss1" })
  end)
end

return function()
  test_cast_with_a_cast_time_resolves_at_the_end()
  test_interrupt_cancels_the_pending_effect()
  test_interrupt_is_refused_for_a_cast_that_cannot_be_interrupted_assumed()
  test_an_instant_cast_logs_success_and_runs_the_effect()
  test_dispel_logs_then_removes_the_aura()
  test_cast_failed_logs_the_failed_type()
  test_stack_increase_logs_applied_dose()
  test_aura_logs_applied_before_the_unit_aura_event()
end
