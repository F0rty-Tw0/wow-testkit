-- SimEffects: what a landed cast does at once (damage, projectiles, auras, energize, areas, triggers) and the effect ring the
-- world reads; test_sim_effects_ongoing.lua has the areas and runs that take time. Every record is a kit literal (tests/helpers/sim_spells.lua).
local A = require("assert")
local Actors = require("combat_actors")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SP = require("tests.helpers.sim_spells")
local SimEffects = require("sim_effects")
local SimSpells = require("sim_spells")

local KIT, OTHER = 900001, 900002

local function test_damage_aura_and_energize_effects()
  local rec = SP.record({
    duration = 8000,
    effects = {
      { type = "damage", base = 19, target = "enemy" },
      { type = "aura", aura = "root", base = 0, target = "enemy" },
      { type = "energize", base = 9, target = "caster" },
    },
  })
  SP.withSpells("retail", { rec }, function(w, s, player)
    local foe = SP.target(w, player)
    local unit = SH.record(w, { "UNIT_AURA", "UNIT_POWER_UPDATE" })
    SimSpells.cast(w, player, KIT)
    A.eq(foe.health, 81)
    A.eq(foe.auras[1].root, true) -- kit-only field, hidden from addons
    A.eq(foe.auras[1].isHarmful, true)
    A.eq(_G.UnitPower("player", 1), 9)
    A.same(SP.subevents(w), { "SPELL_DAMAGE", "SPELL_AURA_APPLIED", "SPELL_ENERGIZE" })
    A.same({ unit[1].event, unit[#unit].event }, { "UNIT_AURA", "UNIT_POWER_UPDATE" })
    local energize = w.combat.log.entries[#w.combat.log.entries]
    A.same({ energize[12], energize[15], energize[16], energize[17], energize[18] }, { KIT, 9, 0, player.powerType, 0 })
    s:simStep(8.1)
    A.eq(#foe.auras, 0)
    A.eq(SP.subevents(w)[#SP.subevents(w)], "SPELL_AURA_REMOVED")
    A.eq(SP.hitsOn(w, "SPELL_AURA_REMOVED", foe.guid), 1)
    A.same(w.sim.spellAuras, {})
  end)
end

local function test_a_spell_aura_is_on_record_until_it_goes()
  local rec = SP.record({ duration = 8000, effects = { { type = "aura", aura = "stun", target = "enemy" } } })
  SP.withSpells("retail", { rec }, function(w, s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    local id = foe.auras[1].auraInstanceID
    A.same(w.sim.spellAuras[foe.guid .. "/" .. id], { spellID = KIT, casterGuid = player.guid, targetGuid = foe.guid, style = "stun" })
    A.same(SP.effectsOfKind(w, "aura"), { { kind = "aura", guid = foe.guid, spellID = KIT, style = "stun" } })
    s:simStep(8.1)
    A.same(SP.effectsOfKind(w, "aura"), {})
  end)
end

local function test_an_actor_that_leaves_takes_its_aura_records_along()
  local rec = SP.record({ duration = 8000, effects = { { type = "aura", aura = "root", target = "enemy" } } })
  SP.withSpells("retail", { rec }, function(w, _s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    Actors.remove(w, foe)
    A.same({ w.sim.spellAuras, SP.effectsOfKind(w, "aura") }, { {}, {} })
  end)
end

local function test_periodic_and_dummy_auras_hold_neither_root_nor_stun()
  local rec = SP.record({ duration = 5000, effects = { { type = "aura", aura = "dummy", target = "caster" } } })
  SP.withSpells("retail", { rec }, function(w, _s, player)
    SimSpells.cast(w, player, KIT)
    local aura = player.auras[1]
    A.same({ aura.root, aura.stun, aura.isHelpful, aura.duration }, { nil, nil, true, 5 })
    A.same(SP.effectsOfKind(w, "aura"), {}) -- the scene shows only root and stun
  end)
end

local function test_damage_base_rounds_down_assumed()
  SP.withSpells("retail", { SP.record({ effects = { { type = "damage", base = 19.7, target = "enemy" } } }) }, function(w, _s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    A.eq(foe.health, 81)
  end)
end

local function test_energize_stops_at_the_maximum()
  SP.withSpells("retail", { SP.record({ effects = { { type = "energize", base = 150, target = "caster" } } }) }, function(w, _s, player)
    SimSpells.cast(w, player, KIT)
    A.eq(player.power, 100)
    local entry = w.combat.log.entries[#w.combat.log.entries]
    A.same({ entry[2], entry[15], entry[16] }, { "SPELL_ENERGIZE", 150, 50 })
  end)
end

local function test_energize_reports_the_part_past_the_maximum_from_the_current_power()
  SP.withSpells("retail", { SP.record({ effects = { { type = "energize", base = 9, target = "caster" } } }) }, function(w, _s, player)
    Actors.setPower(w, player, 95)
    SimSpells.cast(w, player, KIT)
    local entry = w.combat.log.entries[#w.combat.log.entries]
    A.same({ player.power, entry[15], entry[16] }, { 100, 9, 4 })
  end)
end

local function test_projectile_lands_after_its_travel_time_assumed()
  local rec = SP.record({ castTime = 2500, maxRange = 40, effects = { { type = "damage", base = 10, target = "enemy" } } })
  SP.withSpells("retail", { rec }, function(w, s, player)
    local foe = SP.target(w, player, 0, 17) -- 24 yd away after both reaches
    SimSpells.cast(w, player, KIT)
    s:simStep(2.5)
    A.eq(foe.health, 100)
    local flying = SP.effectsOfKind(w, "projectile")
    local launched = flying[1] and flying[1].t
    A.same(flying, { { kind = "projectile", from = { x = 0, y = -10 }, to = { x = 0, y = 17 }, spellID = KIT, t = launched } })
    A.eq(launched ~= nil and launched > w.now - 0.1 and launched <= w.now, true, "it is launched when the bar ends")
    s:simStep(0.9)
    A.eq(foe.health, 100)
    s:simStep(0.2)
    A.eq(foe.health, 90)
    A.eq(#SP.effectsOfKind(w, "hit"), 1)
  end)
end

local function test_a_projectile_for_a_foe_that_is_gone_hits_nothing()
  local rec = SP.record({ castTime = 1000, maxRange = 40, effects = { { type = "damage", base = 10, target = "enemy" } } })
  SP.withSpells("retail", { rec }, function(w, s, player)
    local foe = SP.target(w, player, 0, 17)
    SimSpells.cast(w, player, KIT)
    s:simStep(1.1)
    Actors.remove(w, foe)
    s:simStep(1.2)
    A.same(w.errors, {})
    A.eq(SP.hitsOn(w, "SPELL_DAMAGE", foe.guid), 0)
  end)
end

local function test_a_projectile_for_a_foe_killed_in_flight_hits_nothing()
  local rec = SP.record({ castTime = 1000, maxRange = 40, effects = { { type = "damage", base = 10, target = "enemy" } } })
  SP.withSpells("retail", { rec }, function(w, s, player)
    local foe = SP.target(w, player, 0, 17)
    SimSpells.cast(w, player, KIT)
    s:simStep(1.1)
    Resolve.kill(w, foe)
    s:simStep(1.2)
    A.same({ SP.hitsOn(w, "SPELL_DAMAGE", foe.guid), #SP.effectsOfKind(w, "hit") }, { 0, 0 })
  end)
end

local function test_a_timed_spell_whose_foe_left_the_world_hits_nothing()
  local rec = SP.record({ castTime = 1000, maxRange = 8, effects = { { type = "damage", base = 10, target = "enemy" } } })
  SP.withSpells("retail", { rec }, function(w, s, player)
    local foe = SP.target(w, player, 0, -3)
    SimSpells.cast(w, player, KIT)
    s:simStep(0.5)
    Actors.remove(w, foe)
    s:simStep(1)
    A.same({ SP.hitsOn(w, "SPELL_DAMAGE", foe.guid), #SP.effectsOfKind(w, "hit"), w.errors }, { 0, 0, {} })
  end)
end

local function test_a_charge_with_no_target_does_nothing()
  local first = SP.record({ effects = { { type = "trigger", trigger = OTHER, target = "caster" } } })
  local second = SP.record({ id = OTHER, effects = { { type = "charge", target = "enemy" }, { type = "energize", base = 9, target = "caster" } } })
  SP.withSpells("retail", { first, second }, function(w, _s, player)
    A.eq(SimSpells.cast(w, player, KIT), true) -- a self trigger needs no target
    A.same({ w.sim.charge, w.sim.driven, w.errors, _G.UnitPower("player", 1) }, { nil, nil, {}, 9 })
    A.eq(#SP.effectsOfKind(w, "charge"), 0)
  end)
end

local function test_a_short_or_instant_spell_hits_at_once_assumed()
  for _, shape in ipairs({ { castTime = 1000, maxRange = 8 }, { castTime = 0, maxRange = 40 } }) do
    local rec = SP.record({ castTime = shape.castTime, maxRange = shape.maxRange, effects = { { type = "damage", base = 10, target = "enemy" } } })
    SP.withSpells("retail", { rec }, function(w, s, player)
      local foe = SP.target(w, player, 0, -3) -- 5 yd away after both reaches
      SimSpells.cast(w, player, KIT)
      s:simStep(1)
      A.eq(foe.health, 90, shape.castTime)
      A.eq(#SP.effectsOfKind(w, "projectile"), 0)
    end)
  end
end

local function test_area_around_the_caster_hits_hostiles_up_to_the_radius()
  local effects =
    { { type = "damage", base = 10, target = "areaSource", radius = 8 }, { type = "aura", aura = "root", target = "areaSource", radius = 8 } }
  SP.withSpells("retail", { SP.record({ duration = 4000, effects = effects }) }, function(w, _s, player)
    -- The reach of a foe is 1.5 yd, so a centre 6.5 yd away is 5 yd from the caster.
    local near = SH.foe(w, 0, -3.5)
    local inside = SH.foe(w, 0, -0.6) -- 7.9 yd
    local edge = SH.foe(w, 0, -0.5) -- 8.0 yd: the radius counts
    local outside = SH.foe(w, 0, -0.4) -- 8.1 yd
    local friend = SH.foe(w, 0, -5, { hostile = false })
    local dead = SH.foe(w, 0, -4, { isDead = true })
    SimSpells.cast(w, player, KIT) -- no target needed: every effect is around the caster
    A.same({ near.health, inside.health, edge.health, outside.health, friend.health }, { 90, 90, 90, 100, 100 })
    A.same({ #near.auras, #inside.auras, #edge.auras, #outside.auras, #friend.auras, #dead.auras }, { 1, 1, 1, 0, 0, 0 })
    A.eq(#SP.subevents(w), 6) -- three damages and three auras
  end)
end

local function test_area_around_a_point_hits_the_hostiles_there()
  local effects = { { type = "damage", base = 10, target = "areaDest", radius = 8 } }
  SP.withSpells("retail", { SP.record({ ground = true, effects = effects }) }, function(w, _s, player)
    local there, elsewhere = SH.foe(w, 0, 10), SH.foe(w, 0, -5)
    A.eq(SimSpells.cast(w, player, KIT, nil, { x = 0, y = 12 }), true)
    A.same({ there.health, elsewhere.health }, { 90, 100 })
  end)
end

local function test_an_unknown_effect_type_is_ignored_and_counted()
  local effects = { { type = "mystery", base = 1, target = "enemy" }, { type = "damage", base = 10, target = "enemy" } }
  SP.withSpells("retail", { SP.record({ effects = effects }) }, function(w, _s, player)
    local foe = SP.target(w, player)
    A.eq(SimSpells.cast(w, player, KIT), true)
    A.same({ foe.health, w.unscripted["sim:effect:mystery"] }, { 90, 1 })
  end)
end

local function test_a_trigger_plays_the_effects_of_the_other_spell_on_the_same_target()
  local first = SP.record({ effects = { { type = "trigger", trigger = OTHER, target = "enemy" } } })
  local second = SP.record({ id = OTHER, effects = { { type = "damage", base = 7, target = "enemy" } } })
  SP.withSpells("retail", { first, second }, function(w, _s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    A.eq(foe.health, 93)
  end)
end

local function test_a_spell_that_triggers_itself_stops_at_the_depth_limit()
  local effects = { { type = "damage", base = 5, target = "enemy" }, { type = "trigger", trigger = KIT, target = "enemy" } }
  SP.withSpells("retail", { SP.record({ effects = effects }) }, function(w, _s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    A.eq(foe.health, 100 - 5 * SimEffects.MAX_TRIGGER_DEPTH)
  end)
end

local function test_the_ring_keeps_two_seconds_of_events()
  local rec = SP.record({ effects = { { type = "damage", base = 10, target = "enemy" } } })
  SP.withSpells("retail", { rec }, function(w, s, player)
    SP.target(w, player)
    SimSpells.cast(w, player, KIT)
    A.eq(#SP.effectsOfKind(w, "hit"), 1)
    s:simStep(1.9)
    A.eq(#SP.effectsOfKind(w, "hit"), 1)
    s:simStep(0.2)
    A.eq(#SP.effectsOfKind(w, "hit"), 0)
    A.eq(#w.sim.fx, 0, "the ring drops what the world no longer shows")
  end)
end

local function test_a_flavor_free_damage_cast_on_every_flavor()
  for _, flavor in ipairs(SP.FLAVORS) do
    SP.withSpells(flavor, { SP.record({ effects = { { type = "damage", base = 10, target = "enemy" } } }) }, function(w, _s, player)
      local foe = SP.target(w, player)
      SimSpells.cast(w, player, KIT)
      A.eq(foe.health, 90, flavor)
    end)
  end
end

return function()
  test_damage_aura_and_energize_effects()
  test_a_spell_aura_is_on_record_until_it_goes()
  test_an_actor_that_leaves_takes_its_aura_records_along()
  test_periodic_and_dummy_auras_hold_neither_root_nor_stun()
  test_damage_base_rounds_down_assumed()
  test_energize_stops_at_the_maximum()
  test_energize_reports_the_part_past_the_maximum_from_the_current_power()
  test_projectile_lands_after_its_travel_time_assumed()
  test_a_projectile_for_a_foe_that_is_gone_hits_nothing()
  test_a_projectile_for_a_foe_killed_in_flight_hits_nothing()
  test_a_timed_spell_whose_foe_left_the_world_hits_nothing()
  test_a_charge_with_no_target_does_nothing()
  test_a_short_or_instant_spell_hits_at_once_assumed()
  test_area_around_the_caster_hits_hostiles_up_to_the_radius()
  test_area_around_a_point_hits_the_hostiles_there()
  test_an_unknown_effect_type_is_ignored_and_counted()
  test_a_trigger_plays_the_effects_of_the_other_spell_on_the_same_target()
  test_a_spell_that_triggers_itself_stops_at_the_depth_limit()
  test_the_ring_keeps_two_seconds_of_events()
  test_a_flavor_free_damage_cast_on_every_flavor()
end
