-- SimGround: the targeting mode of a ground spell (spec 7.6). A ground spell cast with no point opens it, a left click on the
-- ground casts at that point (out of range: the error, and the mode stays), a right click, Esc or a stun ends it. Every
-- record is a kit literal (tests/helpers/sim_spells.lua); no extract is read.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.session")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SP = require("tests.helpers.sim_spells")
local Sim = require("sim")
local SimSpellData = require("sim_spell_data")
local SimSpells = require("sim_spells")
local SimTarget = require("sim_target")
local SimWorld = require("sim_world")

local BLIZZ, OTHER = 900001, 900002
local EVENTS = { "UI_ERROR_MESSAGE", "CURRENT_SPELL_CAST_CHANGED" }

-- The player is at (0, -10), so a point (0, y) is y + 10 yards away.
local function blizzard(over)
  local rec = {
    ground = true,
    maxRange = 30,
    castTime = 0,
    duration = 8000,
    effects = { { type = "persistent", base = 10, radius = 8, target = "areaDest" } },
  }
  for key, value in pairs(over or {}) do
    rec[key] = value
  end

  return SP.record(rec)
end

local function names(log)
  local out = {}
  for i, entry in ipairs(log) do
    out[i] = entry.event
  end

  return out
end

-- Review Focus 5: an out-of-range ground click errors and the mode stays.
local function test_out_of_range_click_errors_and_stays_targeting()
  for _, flavor in ipairs(SP.FLAVORS) do
    SP.withSpells(flavor, { blizzard() }, function(w, s, player)
      SH.foe(w, 0, 20)
      A.eq(SimSpells.cast(w, player, BLIZZ), true)
      A.eq(_G.SpellIsTargeting(), true, flavor)
      A.same(w.sim.targeting, { spellID = BLIZZ, radius = 8 })
      local log = SH.record(w, EVENTS)
      s:clickGround(0, 55)
      A.eq(log[1].event, "UI_ERROR_MESSAGE")
      A.eq(log[1][4], _G.SPELL_FAILED_OUT_OF_RANGE)
      A.same({ #log, _G.SpellIsTargeting(), #w.sim.areas }, { 1, true, 0 })
      s:clickGround(0, 15)
      A.same({ _G.SpellIsTargeting(), #w.sim.areas, w.sim.targeting }, { false, 1, nil })
      A.eq(log[#log].event, "CURRENT_SPELL_CAST_CHANGED")
      A.same({ #log, log[#log][3] }, { 2, false })
    end)
  end
end

-- The player reaches 1.5 yards (SimRange.REACH) and a point has none, so 30 yards of range ends 31.5 yards from the centre.
local function test_the_max_range_edge_casts_and_a_hair_past_it_errors()
  SP.withSpells("retail", { blizzard() }, function(w, s, player)
    SimSpells.cast(w, player, BLIZZ)
    local log = SH.record(w, { "UI_ERROR_MESSAGE" })
    s:clickGround(0, 21.51)
    A.same({ #log, _G.SpellIsTargeting() }, { 1, true })
    s:clickGround(0, 21.5)
    A.same({ #log, _G.SpellIsTargeting(), #w.sim.areas }, { 1, false, 1 })
  end)
end

local function test_a_right_click_and_the_stop_fakes_cancel_with_one_event_and_no_cost()
  SP.withSpells("retail", { blizzard({ cooldown = 9000, gcd = 1500 }) }, function(w, s, player)
    local log = SH.record(w, EVENTS)
    SimSpells.cast(w, player, BLIZZ)
    A.same({ names(log), log[1][3] }, { { "CURRENT_SPELL_CAST_CHANGED" }, false })
    A.eq(s:clickGround(0, 0, "RightButton"), true)
    A.same({ _G.SpellIsTargeting(), #log, log[2][3] }, { false, 2, true })
    A.same({ _G.SpellStopTargeting(), #log }, { false, 2 })
    SimSpells.cast(w, player, BLIZZ)
    A.same({ _G.SpellStopTargeting(), _G.SpellStopTargeting(), #log, log[4][3] }, { true, false, 4, true })
    A.same({ #w.sim.areas, { SimSpells.cooldown(w, BLIZZ) }, w.sim.gcdEnd }, { 0, { 0, 0 }, 0 })
  end)
end

local function test_escape_cancels_the_mode_and_does_not_open_the_menu()
  SP.withSpells("retail", { blizzard() }, function(w, s, player)
    local menus = 0
    _G.ToggleGameMenu = function()
      menus = menus + 1
    end
    local log = SH.record(w, { "CURRENT_SPELL_CAST_CHANGED" })
    SimSpells.cast(w, player, BLIZZ)
    s:key("ESCAPE", "down")
    s:key("ESCAPE", "up")
    A.same({ _G.SpellIsTargeting(), menus, #log, log[2][3] }, { false, 0, 2, true })
    s:key("ESCAPE", "down")
    A.eq(menus, 1, "with nothing to cancel the menu opens")
  end)
end

local function test_spell_stop_casting_ends_the_mode_too()
  SP.withSpells("retail", { blizzard() }, function(w, _, player)
    SimSpells.cast(w, player, BLIZZ)
    A.same({ _G.SpellStopCasting(), _G.SpellIsTargeting(), _G.SpellStopCasting() }, { true, false, false })
  end)
end

local function test_a_unit_click_is_swallowed_and_the_target_stays()
  SP.withSpells("retail", { blizzard() }, function(w, s, player)
    local first, second = SP.target(w, player, 0, 10), SH.foe(w, 5, 10)
    SimSpells.cast(w, player, BLIZZ)
    s:clickUnit(second)
    s:clickUnit(second, "RightButton")
    A.same({ player.targetGuid, _G.SpellIsTargeting() }, { first.guid, false })
    SimSpells.cast(w, player, BLIZZ)
    s:clickUnit(second)
    A.same({ player.targetGuid, _G.SpellIsTargeting(), #w.sim.areas }, { first.guid, true, 0 })
  end)
end

local function test_hover_still_works_in_the_mode()
  SP.withSpells("retail", { blizzard() }, function(w, _, player)
    local foe = SH.foe(w, 0, 10)
    SimSpells.cast(w, player, BLIZZ)
    A.eq(Actors.get(w, "mouseover"), nil)
    A.eq(SimTarget.pointer(w, "enter", { guid = foe.guid }), true)
    A.eq(Actors.get(w, "mouseover"), foe)
  end)
end

local function test_spell_target_unit_casts_at_the_units_place()
  SP.withSpells("retail", { blizzard() }, function(w, _, player)
    local foe = SP.target(w, player, 3, 10)
    A.eq(_G.SpellTargetUnit("target"), nil)
    A.eq(#w.sim.areas, 0, "nothing to aim without the mode")
    SimSpells.cast(w, player, BLIZZ)
    _G.SpellTargetUnit("target")
    A.same({ _G.SpellIsTargeting(), #w.sim.areas, w.sim.areas[1].at }, { false, 1, { x = 3, y = 10 } })
    A.eq(foe.guid, player.targetGuid)
  end)
end

local function test_entering_runs_the_checks_and_a_second_ground_spell_replaces_the_first()
  local small = { { type = "persistent", base = 1, radius = 3, target = "areaDest" } }
  local recs = { blizzard({ cooldown = 9000 }), blizzard({ id = OTHER, effects = small }) }
  SP.withSpells("retail", recs, function(w, s, player)
    SimSpells.cast(w, player, BLIZZ)
    s:clickGround(0, 10)
    local log = SH.record(w, EVENTS)
    A.same({ SimSpells.cast(w, player, BLIZZ) }, { false, "SPELL_FAILED_NOT_READY" })
    A.same({ names(log), _G.SpellIsTargeting() }, { { "UI_ERROR_MESSAGE" }, false })
    A.eq(SimSpells.cast(w, player, OTHER), true)
    A.eq(SimSpells.cast(w, player, OTHER), true)
    A.same(w.sim.targeting, { spellID = OTHER, radius = 3 })
  end)
end

local function test_a_stun_ends_the_mode()
  SP.withSpells("retail", { blizzard() }, function(w, s, player)
    local foe = SH.foe(w, 0, 10)
    SimSpells.cast(w, player, BLIZZ)
    Resolve.aura(w, foe, player, { spellID = 9, duration = 2, harmful = true, stun = true })
    s:simStep(0.1)
    A.eq(_G.SpellIsTargeting(), false)
  end)
end

local function test_walking_keeps_the_mode()
  SP.withSpells("retail", { blizzard() }, function(w, s, player)
    SimSpells.cast(w, player, BLIZZ)
    s:key("W", "down")
    s:simStep(0.5)
    s:key("W", "up")
    A.eq(_G.SpellIsTargeting(), true)
    A.eq(s:clickGround(0, 20), true)
    A.eq(#w.sim.areas, 1)
    A.eq(player.pos.y > -10, true)
  end)
end

local function test_the_cooldown_is_charged_when_the_cast_lands_not_when_the_mode_opens()
  SP.withSpells("retail", { blizzard({ castTime = 2000, cooldown = 9000, gcd = 1500 }) }, function(w, s, player)
    SimSpells.cast(w, player, BLIZZ)
    A.same({ { SimSpells.cooldown(w, BLIZZ) }, w.sim.gcdEnd }, { { 0, 0 }, 0 })
    s:clickGround(0, 10)
    A.same({ _G.SpellIsTargeting(), #w.sim.areas, { SimSpells.cooldown(w, BLIZZ) } }, { false, 0, { 0, 0 } })
    s:simStep(2.1)
    A.same({ #w.sim.areas, select(2, SimSpells.cooldown(w, BLIZZ)) }, { 1, 9 })
  end)
end

-- Runs fn with rec answering SimSpellData.get on every world: what the extract or the class kit's literals do when the fresh
-- world restores, a moment before a test could put anything there.
local function withRecordKnownToEveryWorld(rec, fn)
  local get = SimSpellData.get
  SimSpellData.get = function(w, id)
    return get(w, id) or (id == rec.id and rec or nil)
  end
  local ok, err = pcall(fn)
  SimSpellData.get = get
  if not ok then
    error(err, 0)
  end
end

local function test_a_reload_keeps_the_mode()
  H.withSession({ sim = {} }, function(sess)
    local recs = { blizzard() }
    SP.install(sess.w, recs)
    SimSpells.cast(sess.w, sess.w.sim.player, BLIZZ)
    withRecordKnownToEveryWorld(recs[1], function()
      SH.reloaded(sess, function(fresh)
        local fw = fresh.w
        SP.install(fw, recs)
        A.same({ fw.sim.targeting, _G.SpellIsTargeting() }, { { spellID = BLIZZ, radius = 8 }, true })
        fresh.s:clickGround(0, 10)
        A.same({ _G.SpellIsTargeting(), #fw.sim.areas }, { false, 1 })
      end)
    end)
  end)
end

local function bolt(over)
  local rec = { id = OTHER, effects = { { type = "damage", base = 7, target = "enemy" } } }
  for key, value in pairs(over or {}) do
    rec[key] = value
  end

  return SP.record(rec)
end

-- Review Focus 6 (spec 7.6, cast request while targeting): a request that passes its checks ends the mode, whatever the spell.
local function test_any_cast_that_passes_its_checks_ends_the_mode_and_resolves()
  SP.withSpells("retail", { blizzard(), bolt(), bolt({ id = 900003, castTime = 2000 }) }, function(w, s, player)
    local foe = SP.target(w, player)
    SimSpells.cast(w, player, BLIZZ)
    local log = SH.record(w, EVENTS)
    A.eq(SimSpells.cast(w, player, OTHER), true)
    A.same({ _G.SpellIsTargeting(), foe.health, names(log), log[1][3] }, { false, 93, { "CURRENT_SPELL_CAST_CHANGED" }, false })
    A.eq(w.sim.targeting, nil)
    SimSpells.cast(w, player, BLIZZ)
    A.eq(SimSpells.cast(w, player, 900003), true)
    A.same({ _G.SpellIsTargeting(), player.casting ~= nil, foe.health }, { false, true, 93 })
    s:simStep(3)
    A.eq(foe.health, 86)
  end)
end

local function test_a_cast_that_fails_its_checks_leaves_the_mode()
  SP.withSpells("retail", { blizzard(), bolt({ cooldown = 9000 }) }, function(w, _, player)
    SP.target(w, player)
    SimSpells.cast(w, player, OTHER)
    SimSpells.cast(w, player, BLIZZ)
    A.same({ SimSpells.cast(w, player, OTHER) }, { false, "SPELL_FAILED_NOT_READY" })
    A.same({ _G.SpellIsTargeting(), w.sim.targeting }, { true, { spellID = BLIZZ, radius = 8 } })
  end)
end

local function test_a_reload_drops_a_mode_whose_spell_is_gone()
  H.withSession({ sim = {} }, function(sess)
    SP.install(sess.w, { blizzard() })
    SimSpells.cast(sess.w, sess.w.sim.player, BLIZZ)
    A.eq(_G.SpellIsTargeting(), true)
    SH.reloaded(sess, function(fresh)
      A.same({ fresh.w.sim.targeting, _G.SpellIsTargeting() }, { nil, false })
    end)
  end)
end

local function test_a_world_reset_ends_the_mode_and_the_world_reads_it()
  SP.withSpells("retail", { blizzard() }, function(w, _, player)
    A.eq(SimWorld.build(w).targeting, nil)
    SimSpells.cast(w, player, BLIZZ)
    local read = SimWorld.build(w).targeting
    A.same(read, { spellID = BLIZZ, radius = 8 })
    read.radius = 99
    A.eq(w.sim.targeting.radius, 8, "the read is a copy")
    Sim.reset(w)
    A.same({ w.sim.targeting, _G.SpellIsTargeting() }, { nil, false })
  end)
end

return function()
  test_out_of_range_click_errors_and_stays_targeting()
  test_the_max_range_edge_casts_and_a_hair_past_it_errors()
  test_a_right_click_and_the_stop_fakes_cancel_with_one_event_and_no_cost()
  test_escape_cancels_the_mode_and_does_not_open_the_menu()
  test_spell_stop_casting_ends_the_mode_too()
  test_a_unit_click_is_swallowed_and_the_target_stays()
  test_hover_still_works_in_the_mode()
  test_spell_target_unit_casts_at_the_units_place()
  test_entering_runs_the_checks_and_a_second_ground_spell_replaces_the_first()
  test_a_stun_ends_the_mode()
  test_walking_keeps_the_mode()
  test_the_cooldown_is_charged_when_the_cast_lands_not_when_the_mode_opens()
  test_a_reload_keeps_the_mode()
  test_any_cast_that_passes_its_checks_ends_the_mode_and_resolves()
  test_a_cast_that_fails_its_checks_leaves_the_mode()
  test_a_reload_drops_a_mode_whose_spell_is_gone()
  test_a_world_reset_ends_the_mode_and_the_world_reads_it()
end
