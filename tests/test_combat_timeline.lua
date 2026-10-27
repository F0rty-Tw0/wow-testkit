-- Timeline: scripted combat entries scheduled on the world clock.
local A = require("assert")
local H = require("tests.helpers.combat")
local Timeline = require("combat_timeline")

local S = H.SPELLS

local function test_entries_run_at_their_times_in_order()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    Timeline.run(w, {
      { at = 3, damage = { from = "boss1", to = "party1", amount = 30 } },
      { at = 1, damage = { from = "boss1", to = "party1", amount = 10 } },
      { at = 1, damage = { from = "boss1", to = "party1", amount = 11 } },
    })
    w:advance(0.5)
    A.eq(#c.log.entries, 0)
    w:advance(0.5)
    A.same({ c.log.entries[1][12], c.log.entries[2][12], #c.log.entries }, { 10, 11, 2 })
    w:advance(2)
    A.same({ c.log.entries[3][12], ann.health, brute.health }, { 30, 949, 5000 })
  end)
end

local function test_every_entry_kind_calls_its_resolve_action()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    Timeline.run(w, {
      { at = 1, damage = { from = "boss1", to = "party1", amount = 100, spell = S.STRIKE } },
      { at = 2, heal = { from = "party1", to = "party1", amount = 50, spell = S.MEND } },
      { at = 3, aura = { from = "boss1", to = "party1", spell = S.CURSE, duration = 10 } },
      { at = 4, cast = { from = "boss1", spell = S.BOLT, to = "party1" } },
      { at = 5, interrupt = { from = "party1", to = "boss1", spell = S.STRIKE } },
      { at = 6, kill = "boss1" },
    })
    w:advance(6)
    A.same(H.subevents(c), { "SPELL_DAMAGE", "SPELL_HEAL", "SPELL_AURA_APPLIED", "SPELL_CAST_START", "SPELL_INTERRUPT", "UNIT_DIED" })
    A.same({ ann.health, #ann.auras, brute.isDead }, { 950, 1, true })
  end)
end

local function test_a_pull_entry_engages_the_enemy()
  H.withCombat("retail", function(w)
    H.pair(w)
    local log = H.watch(w, { "PLAYER_REGEN_DISABLED" })
    Timeline.run(w, { { at = 2, pull = "boss1" } })
    w:advance(1)
    A.eq(#log, 0)
    w:advance(1)
    A.eq(#log, 1)
  end)
end

local function test_an_unknown_token_raises_before_anything_is_scheduled()
  H.withCombat("retail", function(w)
    H.pair(w)
    local timers = #w.timers
    local ok, err = pcall(Timeline.run, w, {
      { at = 1, kill = "boss1" },
      { at = 2, damage = { from = "boss1", to = "nobody", amount = 5 } },
    }, "s:combat")
    A.eq(ok, false)
    A.contains(err, "s:combat")
    A.contains(err, "nobody")
    A.eq(#w.timers, timers)
  end)
end

local function test_an_entry_needs_a_time_and_exactly_one_action()
  H.withCombat("retail", function(w)
    H.pair(w)
    A.errors(function()
      Timeline.run(w, { { kill = "boss1" } })
    end, "at")
    A.errors(function()
      Timeline.run(w, { { at = 1, kill = "boss1", pull = "boss1" } })
    end, "exactly one")
    A.errors(function()
      Timeline.run(w, { { at = 1 } })
    end, "exactly one")
  end)
end

return function()
  test_entries_run_at_their_times_in_order()
  test_every_entry_kind_calls_its_resolve_action()
  test_a_pull_entry_engages_the_enemy()
  test_an_unknown_token_raises_before_anything_is_scheduled()
  test_an_entry_needs_a_time_and_exactly_one_action()
end
