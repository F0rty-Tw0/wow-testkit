-- SimSpells state and seams: the cast fakes, the seam the effects hang on, a world reset and a reload. Every record is a kit
-- literal (tests/helpers/sim_spells.lua); no extract is read. test_sim_spells.lua has the pipeline itself.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.session")
local Sim = require("sim")
local SH = require("tests.helpers.sim_combat")
local SP = require("tests.helpers.sim_spells")
local SimSpells = require("sim_spells")

local KIT, OTHER = 900001, 900002

local function target(w, player, x, y)
  local foe = SH.foe(w, x or 0, y or 10)
  Actors.setTarget(w, player, foe)

  return foe
end

local function test_the_cast_fakes_play_the_pipeline()
  SP.withSpells("retail", { SP.record() }, function(w, _, player)
    target(w, player)
    local log = SH.record(w, { "UNIT_SPELLCAST_SUCCEEDED" })
    w.mock.actions[1] = { type = "spell", id = KIT }
    w.mock.actions[2] = { type = "item", id = KIT }
    _G.UseAction(2)
    A.eq(#log, 0, "only a spell slot casts")
    _G.UseAction(1)
    _G.CastSpellByID(KIT)
    _G.CastSpellByName("Kit Bolt")
    _G.CastSpellByName("No Such Spell")
    A.eq(#log, 3)
    Actors.setTarget(w, player, nil)
    Actors.bind(w, SH.foe(w, 0, 12), "mouseover")
    _G.CastSpellByID(KIT, "mouseover")
    A.eq(#log, 4, "an explicit unit token is the target")
  end)
end

local function test_spell_stop_casting_cancels_the_bar()
  SP.withSpells("retail", { SP.record({ castTime = 2500 }) }, function(w, _, player)
    target(w, player)
    local log = SH.record(w, { "UNIT_SPELLCAST_INTERRUPTED" })
    A.eq(_G.SpellStopCasting(), false, "nothing to stop")
    A.eq(_G.CastSpellByID(KIT), nil)
    A.eq(_G.SpellStopCasting(), true, "the Esc chain stops here")
    A.same({ #log, player.cast, player.casting }, { 1, nil, nil })
  end)
end

local function test_the_cast_seam_runs_after_success_only()
  SP.withSpells("retail", { SP.record({ castTime = 1000 }), SP.record({ id = OTHER }) }, function(w, s, player)
    local foe = target(w, player)
    local seen = {}
    table.insert(w.sim.seams.cast, function(_, caster, rec, hit, point)
      seen[#seen + 1] = { caster, rec.id, hit, point }
    end)
    A.same({ w.sim.seams.swing, w.sim.seams.pointer }, { {}, {} })
    SimSpells.cast(w, player, OTHER)
    A.same(seen, { { player, OTHER, foe, nil } })
    SimSpells.cast(w, player, KIT)
    A.eq(#seen, 1, "nothing before the bar fills")
    SimSpells.stop(w, player)
    s:simStep(2)
    A.eq(#seen, 1, "nothing for an interrupted cast")
    Actors.setPos(w, foe, 0, 60)
    A.eq(SimSpells.cast(w, player, OTHER), false)
    A.eq(#seen, 1, "nothing for a cast that fails its checks")
  end)
end

local function test_reset_drops_the_cast_and_the_cooldowns()
  SP.withSpells("retail", { SP.record({ castTime = 1000, cooldown = 9000 }), SP.record({ id = OTHER, cooldown = 9000 }) }, function(w, _, player)
    target(w, player)
    SimSpells.cast(w, player, OTHER)
    SimSpells.cast(w, player, KIT)
    Sim.reset(w)
    A.same({ player.cast, player.casting, SimSpells.cooldown(w, OTHER), w.sim.gcdEnd }, { nil, nil, 0, 0 })
    A.eq(_G.C_Spell.GetSpellCooldown(OTHER).duration, 0)
  end)
end

local function test_reset_clears_the_gcd_of_an_instant_spell_from_the_readers()
  SP.withSpells("retail", { SP.record({ gcd = 1500 }) }, function(w, s, player)
    target(w, player)
    SimSpells.cast(w, player, KIT)
    s:simStep(0.1)
    A.eq(_G.C_Spell.GetSpellCooldown(KIT).duration, 1.5)
    Sim.reset(w)
    A.same({ w.sim.gcdEnd, _G.C_Spell.GetSpellCooldown(KIT).duration }, { 0, 0 })
  end)
end

local function test_a_reload_mid_cast_keeps_no_gcd()
  H.withSession({ sim = {} }, function(sess)
    local recs = { SP.record({ castTime = 3000, gcd = 1500 }), SP.record({ id = OTHER, gcd = 1500 }) }
    SP.install(sess.w, recs)
    target(sess.w, sess.w.sim.player)
    SimSpells.cast(sess.w, sess.w.sim.player, KIT)
    sess.s:simStep(0.5)
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, recs)
      target(fw, fw.sim.player)
      A.eq(SimSpells.cast(fw, fw.sim.player, OTHER), true, "the dropped cast leaves no GCD")
      A.eq(_G.C_Spell.GetSpellCooldown(KIT).duration, 0, "and none on the readers")
    end)
  end)
end

local function test_a_reload_mid_gcd_shows_the_gcd_on_the_readers()
  H.withSession({ sim = {} }, function(sess)
    local recs = { SP.record({ gcd = 1500 }), SP.record({ id = OTHER, gcd = 1500 }) }
    SP.install(sess.w, recs)
    target(sess.w, sess.w.sim.player)
    SimSpells.cast(sess.w, sess.w.sim.player, KIT)
    local started = sess.w.now
    sess.s:simStep(0.5)
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, recs)
      target(fw, fw.sim.player)
      local info = _G.C_Spell.GetSpellCooldown(KIT)
      A.same({ info.startTime, info.duration }, { started, 1.5 })
      A.eq(select(2, SimSpells.cast(fw, fw.sim.player, OTHER)), "SPELL_FAILED_NOT_READY", "the GCD is still enforced")
      fresh.s:simStep(1.1)
      A.eq(SimSpells.cast(fw, fw.sim.player, OTHER), true)
    end)
  end)
end

local function test_a_reload_keeps_the_cooldown_and_drops_the_cast()
  H.withSession({ sim = {} }, function(sess)
    local recs = { SP.record({ cooldown = 30000 }), SP.record({ id = OTHER, castTime = 3000 }) }
    SP.install(sess.w, recs)
    local player = sess.w.sim.player
    target(sess.w, player)
    SimSpells.cast(sess.w, player, KIT)
    sess.s:simStep(2)
    SimSpells.cast(sess.w, player, OTHER)
    local start, duration = SimSpells.cooldown(sess.w, KIT)
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      SP.install(fw, recs)
      A.same({ SimSpells.cooldown(fw, KIT) }, { start, duration })
      local info = _G.C_Spell.GetSpellCooldown(KIT)
      A.same({ info.startTime, info.duration }, { start, duration })
      A.same({ _G.UnitCastingInfo("player"), fw.sim.player.casting, fw.errors }, { nil, nil, {} })
      A.eq(select(2, SimSpells.cast(fw, fw.sim.player, KIT)), "SPELL_FAILED_NOT_READY")
      fresh.s:simStep(29)
      A.eq(SimSpells.cast(fw, fw.sim.player, KIT), true)
    end)
  end)
end

return function()
  test_the_cast_fakes_play_the_pipeline()
  test_spell_stop_casting_cancels_the_bar()
  test_the_cast_seam_runs_after_success_only()
  test_reset_drops_the_cast_and_the_cooldowns()
  test_reset_clears_the_gcd_of_an_instant_spell_from_the_readers()
  test_a_reload_mid_cast_keeps_no_gcd()
  test_a_reload_mid_gcd_shows_the_gcd_on_the_readers()
  test_a_reload_keeps_the_cooldown_and_drops_the_cast()
end
