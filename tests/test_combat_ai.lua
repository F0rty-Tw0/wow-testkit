-- AI: rule timers on the world clock that call Resolve with the rules' own numbers.
local A = require("assert")
local Actors = require("combat_actors")
local Ai = require("combat_ai")
local H = require("tests.helpers.combat")
local Log = require("combat_log")
local Resolve = require("combat_resolve")
local State = require("combat_state")
local Threat = require("combat_threat")

-- Ann (party1), Cal (party2) and Brute (boss1).
local function trio(w)
  local ann, brute = H.pair(w)
  local cal = Actors.add(w, { kind = "player", name = "Cal", token = "party2", health = 1000, healthMax = 1000 })
  return ann, cal, brute
end

-- The destGUIDs of the log entries with this subevent.
local function destinations(c, subevent)
  local out = {}
  for _, entry in ipairs(c.log.entries) do
    if entry[2] == subevent then
      out[#out + 1] = entry[8]
    end
  end
  return out
end

local function test_enemy_swings_on_its_timer_at_top_threat()
  H.withCombat("retail", function(w, c)
    local ann, cal, brute = trio(w)
    brute.ai = { swing = { every = 2, damage = 100 } }
    Threat.add(w, brute, ann, 500)
    Threat.add(w, brute, cal, 100)
    local t0 = Log.timestamp(w)
    Ai.start(w, brute)
    w:advance(4)
    A.same(destinations(c, "SWING_DAMAGE"), { ann.guid, ann.guid })
    A.same({ c.log.entries[1][1] - t0, c.log.entries[2][1] - t0 }, { 2, 4 })
    Threat.add(w, brute, cal, 800) -- Cal now leads with 900
    w:advance(2)
    A.same(destinations(c, "SWING_DAMAGE"), { ann.guid, ann.guid, cal.guid })
  end)
end

local function test_a_second_start_adds_no_second_timer()
  H.withCombat("retail", function(w, c)
    local ann, _, brute = trio(w)
    brute.ai = { swing = { every = 2, damage = 100 } }
    State.engage(w, brute, ann)
    Ai.start(w, brute)
    Ai.start(w, brute)
    w:advance(2)
    A.eq(#destinations(c, "SWING_DAMAGE"), 1)
  end)
end

local function test_enemy_without_threat_swings_at_the_first_engaged_foe()
  H.withCombat("retail", function(w, c)
    local ann, cal, brute = trio(w)
    brute.ai = { swing = { every = 1, damage = 10 } }
    State.engage(w, brute, cal)
    State.engage(w, brute, ann)
    Ai.start(w, brute)
    w:advance(1)
    A.same(destinations(c, "SWING_DAMAGE"), { ann.guid }) -- spawn order, not engage order
  end)
end

local function test_random_targets_use_the_worlds_roll()
  H.withCombat("retail", function(w, c)
    local ann, cal, brute = trio(w)
    brute.ai = { targets = "random", swing = { every = 1, damage = 10 } }
    State.engage(w, brute, ann)
    State.engage(w, brute, cal)
    c.random = function(n)
      return n
    end
    Ai.start(w, brute)
    w:advance(1)
    A.same(destinations(c, "SWING_DAMAGE"), { cal.guid })
  end)
end

local function test_a_friendly_damage_dealer_hits_its_target()
  H.withCombat("retail", function(w, c)
    local ann, _, brute = trio(w)
    ann.ai = { role = "dps", swing = { every = 1, damage = 50 } }
    Actors.setTarget(w, ann, brute)
    Ai.start(w, ann)
    w:advance(1)
    A.same({ brute.health, destinations(c, "SWING_DAMAGE") }, { 4950, { brute.guid } })
  end)
end

local function test_healer_heals_the_lowest_ally()
  H.withCombat("retail", function(w, c)
    local ann, cal = trio(w)
    Actors.setHealth(w, ann, 400)
    Actors.setHealth(w, cal, 900)
    cal.ai = { role = "healer", spells = { { spellID = H.SPELLS.MEND, every = 3, heal = 200 } } }
    Ai.start(w, cal)
    w:advance(3)
    A.same({ ann.health, cal.health }, { 600, 900 })
    A.same(destinations(c, "SPELL_HEAL"), { ann.guid })
    w:advance(6) -- Ann reaches 1000 on the third heal, Cal is still at 900
    A.same({ ann.health, cal.health }, { 1000, 900 })
    w:advance(3)
    A.same({ cal.health, #destinations(c, "SPELL_HEAL") }, { 1000, 4 })
    w:advance(3)
    A.eq(#destinations(c, "SPELL_HEAL"), 4) -- nobody is hurt, so no fifth heal
  end)
end

local function test_a_spell_rule_casts_then_damages_at_the_end()
  H.withCombat("retail", function(w, c)
    local ann, _, brute = trio(w)
    brute.ai = { spells = { { spellID = H.SPELLS.BOLT, every = 5, damage = 300, interruptible = false } } }
    State.engage(w, brute, ann)
    Ai.start(w, brute)
    w:advance(5)
    A.same({ H.subevents(c), brute.cast.notInterruptible }, { { "SPELL_CAST_START" }, true })
    w:advance(2)
    A.same(H.subevents(c), { "SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_DAMAGE" })
    A.eq(ann.health, 700)
    w:advance(3) -- the next cast starts at 10 s
    A.eq(H.subevents(c)[4], "SPELL_CAST_START")
  end)
end

local function test_cooldown_fires_once_below_the_threshold()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    ann.ai = { cooldowns = { { spellID = H.SPELLS.WARD, below = 0.5, aura = { duration = 10, absorb = 100 } } } }
    Ai.start(w, ann)
    w:advance(1)
    A.eq(#ann.auras, 0) -- full health
    Actors.setHealth(w, ann, 450)
    w:advance(1)
    A.same({ #ann.auras, ann.absorbs }, { 1, 100 })
    Actors.setHealth(w, ann, 300)
    w:advance(1)
    A.eq(#ann.auras, 1)
  end)
end

local function test_death_stops_the_ai()
  H.withCombat("retail", function(w, c)
    local ann, _, brute = trio(w)
    brute.ai = { swing = { every = 2, damage = 100 } }
    State.engage(w, brute, ann)
    Ai.start(w, brute)
    w:advance(2)
    Resolve.kill(w, brute)
    A.eq(brute.timers, nil) -- stopped by the death, not by the next tick
    local count = #c.log.entries
    w:advance(10)
    A.eq(#c.log.entries, count)
  end)
end

local function test_a_despawn_stops_the_ai()
  H.withCombat("retail", function(w)
    local _, _, brute = trio(w)
    brute.ai = { swing = { every = 2, damage = 100 } }
    Ai.start(w, brute)
    Actors.remove(w, brute)
    A.eq(brute.timers, nil)
    w:advance(10)
  end)
end

local function test_ai_numbers_are_the_rules_numbers()
  H.withCombat("retail", function(w, c)
    local ann, _, brute = trio(w)
    brute.ai = { swing = { every = 1, damage = 37 } }
    State.engage(w, brute, ann)
    Ai.start(w, brute)
    w:advance(1)
    A.same({ c.log.entries[1][12], ann.health }, { 37, 963 })
  end)
end

return function()
  test_enemy_swings_on_its_timer_at_top_threat()
  test_a_second_start_adds_no_second_timer()
  test_enemy_without_threat_swings_at_the_first_engaged_foe()
  test_random_targets_use_the_worlds_roll()
  test_a_friendly_damage_dealer_hits_its_target()
  test_healer_heals_the_lowest_ally()
  test_a_spell_rule_casts_then_damages_at_the_end()
  test_cooldown_fires_once_below_the_threshold()
  test_death_stops_the_ai()
  test_a_despawn_stops_the_ai()
  test_ai_numbers_are_the_rules_numbers()
end
