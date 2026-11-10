-- SimProcs: the proc rules of the kit (spec 7.5). A swing that lands or a dodge fires a rule on its cadence: the overlay glow
-- shows, the rule's aura goes on the player, and the glow hides when it expires, when the overlay spell is cast or when the
-- aura goes. Every record is a kit literal (tests/helpers/sim_spells.lua); no extract is read.
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local H = require("tests.helpers.session")
local SH = require("tests.helpers.sim_combat")
local Sim = require("sim")
local SimHelper = require("tests.helpers.sim")
local SimMelee = require("sim_melee")
local SimMobs = require("sim_mobs")
local SimProcs = require("sim_procs")
local SimSpells = require("sim_spells")
local SP = require("tests.helpers.sim_spells")

local SHOW, HIDE = "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
local OVERLAY, BUFF = 900002, 900003
local RECS = { SP.record({ id = OVERLAY, name = "Kit Revenge" }), SP.record({ id = BUFF, name = "Kit Revenge!" }) }
local GLOW = { SHOW, HIDE }

local function swingRule(over)
  local rule = { id = 1, onEvent = "swing_hit", every = 2, aura = BUFF, overlay = OVERLAY, duration = 15000 }
  for key, value in pairs(over or {}) do
    rule[key] = value
  end

  return rule
end

local function hasAura(actor, spellID)
  for _, aura in ipairs(actor.auras) do
    if aura.spellId == spellID then
      return true
    end
  end

  return false
end

local function overlayed()
  return _G.C_SpellActivationOverlay.IsSpellOverlayed(OVERLAY)
end

-- A foe 1 yard ahead of the player (at (0, -10), facing north) that becomes its target.
local function foeAhead(w, player)
  return SP.target(w, player, 0, -9)
end

-- A mob that never swings back, 1 yard ahead; the only actor the dodge rule applies to.
local function dummyAhead(w, player)
  local mob = SimMobs.spawn(w, { pos = { x = 0, y = -9 }, health = 1000, ai = false })
  Actors.setTarget(w, player, mob)

  return mob
end

-- How many SWING_MISSED lines the combat log holds for each miss type.
local function missesOf(w)
  local out = {}
  for _, entry in ipairs(w.combat.log.entries) do
    if entry[2] == "SWING_MISSED" then
      for i = 3, entry.n do
        if entry[i] == "DODGE" then
          out.DODGE = (out.DODGE or 0) + 1
        end
      end
    end
  end

  return out
end

local function test_a_swing_proc_glows_applies_its_aura_and_hides_when_the_overlay_spell_is_cast()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule() }
    local foe = foeAhead(w, player)
    local log = SH.record(w, GLOW)
    SimMelee.start(w)
    s:simStep(2)
    A.same({ #log, overlayed() }, { 0, false })
    s:simStep(1)
    A.same({ log[1].event, log[1][3], #log }, { SHOW, OVERLAY, 1 })
    A.same({ overlayed(), hasAura(player, BUFF) }, { true, true })
    SimSpells.cast(w, player, BUFF, foe)
    A.same({ #log, overlayed() }, { 1, true })
    SimSpells.cast(w, player, OVERLAY, foe)
    A.same({ log[2].event, log[2][3], #log, overlayed() }, { HIDE, OVERLAY, 2, false })
  end)
end

-- source: assumed (Ruling 5.6-a) casting the spell a proc unlocks uses the proc up: its aura goes with the glow, and the
-- two together hide the glow once.
local function test_casting_the_overlay_spell_removes_the_proc_aura_and_hides_once()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ every = 1 }) }
    local foe = foeAhead(w, player)
    local log = SH.record(w, GLOW)
    SimMelee.start(w)
    s:simStep(0.1)
    SimMelee.stop(w)
    A.same({ hasAura(player, BUFF), overlayed() }, { true, true })
    SimSpells.cast(w, player, OVERLAY, foe)
    A.same({ hasAura(player, BUFF), overlayed(), #log, log[2].event }, { false, false, 2, HIDE })
    s:simStep(20)
    A.eq(#log, 2)
  end)
end

local function test_a_glow_with_no_aura_hides_at_its_duration_and_only_once()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ every = 1, aura = false, duration = 5000 }) }
    foeAhead(w, player)
    local log = SH.record(w, GLOW)
    SimMelee.start(w)
    s:simStep(0.1)
    SimMelee.stop(w)
    A.same({ #log, overlayed(), #player.auras }, { 1, true, 0 })
    s:simStep(4.8)
    A.eq(overlayed(), true)
    s:simStep(0.3)
    A.same({ log[2].event, #log, overlayed() }, { HIDE, 2, false })
    SimHelper.near(log[2].now - log[1].now, 5)
    s:simStep(20)
    A.eq(#log, 2)
  end)
end

local function test_the_aura_ending_hides_the_glow_before_its_timer_and_the_timer_adds_no_second_hide()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ every = 1 }) }
    foeAhead(w, player)
    local log = SH.record(w, GLOW)
    SimMelee.start(w)
    s:simStep(0.1)
    SimMelee.stop(w)
    for _, aura in ipairs({ unpack(player.auras) }) do
      Auras.remove(w, player, aura)
    end
    A.same({ #log, log[2].event, overlayed() }, { 2, HIDE, false })
    s:simStep(20)
    A.eq(#log, 2)
  end)
end

local function test_the_aura_and_the_glow_ending_together_hide_once()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ every = 1, duration = 3000 }) }
    foeAhead(w, player)
    local log = SH.record(w, GLOW)
    SimMelee.start(w)
    s:simStep(0.1)
    SimMelee.stop(w)
    s:simStep(4)
    A.same({ #log, overlayed(), hasAura(player, BUFF) }, { 2, false, false })
  end)
end

local function test_a_rule_that_fires_while_its_glow_runs_extends_it_without_a_second_show_or_aura()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ every = 1, duration = 4000 }) }
    foeAhead(w, player)
    local log = SH.record(w, GLOW)
    SimMelee.start(w)
    s:simStep(6)
    SimMelee.stop(w)
    A.same({ #log, overlayed(), #player.auras }, { 1, true, 1 })
    s:simStep(3.5)
    A.same({ #log, overlayed() }, { 2, false })
  end)
end

local function test_casting_another_spell_hides_nothing()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ every = 1 }) }
    local foe = foeAhead(w, player)
    SimMelee.start(w)
    s:simStep(0.1)
    local log = SH.record(w, GLOW)
    SimSpells.cast(w, player, BUFF, foe)
    A.same({ #log, overlayed() }, { 0, true })
  end)
end

local function test_a_dodge_rule_makes_a_mob_dodge_every_fifth_swing_and_glows()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ onEvent = "dodge", every = 1, aura = false, duration = 5000 }) }
    local mob = dummyAhead(w, player)
    local log = SH.record(w, GLOW)
    SimMelee.start(w)
    s:simStep(8)
    A.same({ player.swings, #log, missesOf(w) }, { 4, 0, {} })
    local before = mob.health
    s:simStep(3)
    A.same({ player.swings, mob.health, missesOf(w), #log, log[1][3] }, { 4, before, { DODGE = 1 }, 1, OVERLAY })
    s:simStep(3)
    A.eq(player.swings, 5, "the next swing lands")
  end)
end

local function test_no_dodge_without_a_rule_for_it_or_against_a_foe_that_is_not_a_mob()
  SP.withSpells("retail", RECS, function(w, s, player)
    local mob = dummyAhead(w, player)
    SimMelee.start(w)
    s:simStep(14)
    A.same({ player.swings, missesOf(w) }, { 6, {} })
    w.sim.procRules = { swingRule({ onEvent = "dodge", every = 1 }) }
    mob.dodgeOff = true
    s:simStep(30)
    A.same(missesOf(w), {})
    SimMelee.stop(w)
    local foe = foeAhead(w, player)
    SimMelee.start(w)
    s:simStep(20)
    A.same({ missesOf(w), foe.mobState }, { {}, nil })
  end)
end

-- aura: the buff the rule applies, or false for a glow with nothing but its own timer.
local function checkGlowAcrossReload(aura)
  H.withSession({ sim = {} }, function(sess)
    local w = sess.w
    SP.install(w, RECS)
    w.sim.procRules = { swingRule({ every = 1, duration = 15000, aura = aura }) }
    foeAhead(w, w.sim.player)
    SimMelee.start(w)
    sess.s:simStep(0.1)
    SimMelee.stop(w)
    sess.s:simStep(5)
    local untilT = w.sim.procs.active[OVERLAY].untilT
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, RECS)
      fw.sim.procRules = { swingRule({ every = 1, duration = 15000, aura = aura }) }
      A.same({ overlayed(), hasAura(fw.sim.player, BUFF) }, { true, aura == BUFF })
      A.eq(fw.sim.procs.active[OVERLAY].untilT, untilT)
      local log = SH.record(fw, GLOW)
      fresh.s:simStep(untilT - fw.now - 0.5)
      A.same({ #log, overlayed() }, { 0, true })
      fresh.s:simStep(1)
      A.same({ #log, log[1].event, overlayed() }, { 1, HIDE, false })
      SimHelper.near(log[1].now, untilT)
    end)
  end)
end

local function test_a_reload_keeps_the_glow_and_hides_it_when_its_time_is_up()
  checkGlowAcrossReload(BUFF)
  checkGlowAcrossReload(false)
end

-- source: assumed (a reload keeps a glow) a glow whose aura did not come back stays dark, even with time left.
local function test_a_reload_leaves_dark_a_glow_whose_aura_did_not_come_back()
  H.withSession({ sim = {} }, function(sess)
    local w = sess.w
    SP.install(w, RECS)
    w.sim.procRules = { swingRule({ every = 1, duration = 15000 }) }
    foeAhead(w, w.sim.player)
    SimMelee.start(w)
    sess.s:simStep(0.1)
    SimMelee.stop(w)
    A.same({ overlayed(), hasAura(w.sim.player, BUFF) }, { true, true })
    w.sim.procs.active[OVERLAY].auraInstanceID = -1 -- the saved glow names an aura the player no longer has
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, RECS)
      fw.sim.procRules = { swingRule({ every = 1, duration = 15000 }) }
      A.same({ overlayed(), fw.sim.procs.active[OVERLAY] }, { false, nil })
      local log = SH.record(fw, GLOW)
      fresh.s:simStep(20)
      A.eq(#log, 0)
    end)
  end)
end

-- source: assumed (a reload keeps a glow) a glow with no aura whose time ran out stays dark: only its timer kept it lit.
local function test_a_reload_leaves_dark_a_glow_with_no_aura_whose_time_ran_out()
  H.withSession({ sim = {} }, function(sess)
    local w = sess.w
    SP.install(w, RECS)
    w.sim.procRules = { swingRule({ every = 1, duration = 15000, aura = false }) }
    foeAhead(w, w.sim.player)
    SimMelee.start(w)
    sess.s:simStep(0.1)
    SimMelee.stop(w)
    A.eq(overlayed(), true)
    w.sim.procs.active[OVERLAY].untilT = w.now - 1 -- the saved glow's time is up
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, RECS)
      fw.sim.procRules = { swingRule({ every = 1, duration = 15000, aura = false }) }
      A.same({ overlayed(), fw.sim.procs.active[OVERLAY] }, { false, nil })
      local log = SH.record(fw, GLOW)
      fresh.s:simStep(1)
      A.eq(#log, 0)
    end)
  end)
end

local function test_a_reload_keeps_the_count_of_a_rule_that_fires_every_second_swing()
  H.withSession({ sim = {} }, function(sess)
    local w = sess.w
    SP.install(w, RECS)
    w.sim.procRules = { swingRule({ every = 2 }) }
    foeAhead(w, w.sim.player)
    SimMelee.start(w)
    sess.s:simStep(0.1)
    SimMelee.stop(w)
    A.eq(overlayed(), false)
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, RECS)
      fw.sim.procRules = { swingRule({ every = 2 }) }
      SimMelee.start(fw)
      fresh.s:simStep(3)
      A.eq(overlayed(), true, "the second landed swing procs across the reload")
    end)
  end)
end

local function test_a_reload_keeps_the_swing_count_that_picks_the_dodge()
  H.withSession({ sim = {} }, function(sess)
    local w = sess.w
    SP.install(w, RECS)
    w.sim.procRules = { swingRule({ onEvent = "dodge", every = 1, aura = false }) }
    dummyAhead(w, w.sim.player)
    SimMelee.start(w)
    sess.s:simStep(8)
    SimMelee.stop(w)
    A.same(missesOf(w), {})
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, RECS)
      fw.sim.procRules = { swingRule({ onEvent = "dodge", every = 1, aura = false }) }
      SimMelee.start(fw)
      fresh.s:simStep(3)
      A.same({ missesOf(fw), overlayed() }, { { DODGE = 1 }, true })
    end)
  end)
end

local function test_a_world_reset_hides_the_glow_and_forgets_the_counts()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ every = 1 }) }
    foeAhead(w, player)
    SimMelee.start(w)
    s:simStep(0.1)
    local log = SH.record(w, GLOW)
    Sim.reset(w)
    A.same({ #log, log[1].event, overlayed(), w.sim.procs.count }, { 1, HIDE, false, {} })
    s:simStep(20)
    A.eq(#log, 1)
  end)
end

local function test_a_world_reset_takes_the_proc_aura_off_with_the_glow()
  SP.withSpells("retail", RECS, function(w, s, player)
    w.sim.procRules = { swingRule({ every = 1 }) }
    foeAhead(w, player)
    SimMelee.start(w)
    s:simStep(0.1)
    SimMelee.stop(w)
    A.same({ hasAura(player, BUFF), overlayed() }, { true, true })
    local log = SH.record(w, GLOW)
    Sim.reset(w)
    A.same({ hasAura(player, BUFF), overlayed(), #log, log[1].event }, { false, false, 1, HIDE })
  end)
end

local function test_the_overlay_query_is_the_namespaced_one_on_every_flavor()
  for _, flavor in ipairs(SP.FLAVORS) do
    SP.withSpells(flavor, RECS, function()
      A.eq(type(_G.C_SpellActivationOverlay.IsSpellOverlayed), "function", flavor)
      A.eq(rawget(_G, "IsSpellOverlayed"), nil, flavor)
      A.eq(_G.C_SpellActivationOverlay.IsSpellOverlayed(OVERLAY), false, flavor)
    end)
  end
end

local function test_rules_read_the_worlds_list_and_an_unset_list_is_empty()
  SP.withSpells("retail", RECS, function(w)
    A.same(SimProcs.rules(w), w.sim.procRules) -- the class kit's rule
    w.sim.procRules = nil
    A.same(SimProcs.rules(w), {})
    local list = { swingRule() }
    w.sim.procRules = list
    A.eq(SimProcs.rules(w), list)
  end)
end

return function()
  test_a_swing_proc_glows_applies_its_aura_and_hides_when_the_overlay_spell_is_cast()
  test_casting_the_overlay_spell_removes_the_proc_aura_and_hides_once()
  test_a_glow_with_no_aura_hides_at_its_duration_and_only_once()
  test_the_aura_ending_hides_the_glow_before_its_timer_and_the_timer_adds_no_second_hide()
  test_the_aura_and_the_glow_ending_together_hide_once()
  test_a_rule_that_fires_while_its_glow_runs_extends_it_without_a_second_show_or_aura()
  test_casting_another_spell_hides_nothing()
  test_a_dodge_rule_makes_a_mob_dodge_every_fifth_swing_and_glows()
  test_no_dodge_without_a_rule_for_it_or_against_a_foe_that_is_not_a_mob()
  test_a_reload_keeps_the_glow_and_hides_it_when_its_time_is_up()
  test_a_reload_leaves_dark_a_glow_whose_aura_did_not_come_back()
  test_a_reload_leaves_dark_a_glow_with_no_aura_whose_time_ran_out()
  test_a_reload_keeps_the_count_of_a_rule_that_fires_every_second_swing()
  test_a_reload_keeps_the_swing_count_that_picks_the_dodge()
  test_a_world_reset_hides_the_glow_and_forgets_the_counts()
  test_a_world_reset_takes_the_proc_aura_off_with_the_glow()
  test_the_overlay_query_is_the_namespaced_one_on_every_flavor()
  test_rules_read_the_worlds_list_and_an_unset_list_is_empty()
end
