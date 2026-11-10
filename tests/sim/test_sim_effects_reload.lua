-- SimEffects through a reload: the aura records a spell left on actors come back with the auras and go with them. Every
-- record is a kit literal (tests/helpers/sim_spells.lua).
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.session")
local SH = require("tests.helpers.sim_combat")
local SP = require("tests.helpers.sim_spells")
local SimSpells = require("sim_spells")

local KIT = 900001

local function test_an_aura_survives_a_reload_and_is_logged_when_it_ends()
  local rec = SP.record({ duration = 8000, effects = { { type = "aura", aura = "stun", target = "enemy" } } })
  H.withSession({ sim = {} }, function(sess)
    SP.install(sess.w, { rec })
    local foe = SP.target(sess.w, sess.w.sim.player)
    SimSpells.cast(sess.w, sess.w.sim.player, KIT)
    sess.s:simStep(2)
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      A.same(SP.effectsOfKind(fw, "aura"), { { kind = "aura", guid = foe.guid, spellID = KIT, style = "stun" } })
      fresh.s:simStep(6.2)
      A.eq(#Actors.get(fw, foe.guid).auras, 0)
      A.eq(SP.hitsOn(fw, "SPELL_AURA_REMOVED", foe.guid), 1)
      A.same(fw.sim.spellAuras, {})
    end)
  end)
end

local function test_a_reload_drops_the_record_of_an_aura_that_had_run_out()
  local effects = { { type = "aura", aura = "stun", target = "enemy" }, { type = "aura", aura = "root", target = "caster" } }
  local rec = SP.record({ duration = 8000, effects = effects })
  H.withSession({ sim = {} }, function(sess)
    SP.install(sess.w, { rec })
    local foe = SP.target(sess.w, sess.w.sim.player)
    SimSpells.cast(sess.w, sess.w.sim.player, KIT)
    sess.s:simStep(2)
    foe.auras[1].expirationTime = sess.w.now -- due this instant: Auras.restore leaves it off
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      local player = fw.sim.player
      local key = player.guid .. "/" .. player.auras[1].auraInstanceID
      local held = { spellID = KIT, casterGuid = player.guid, targetGuid = player.guid, style = "root" }
      A.eq(#Actors.get(fw, foe.guid).auras, 0)
      A.same(fw.sim.spellAuras, { [key] = held }) -- the player's record stays, the foe's is gone
      fresh.s:simStep(7)
      A.eq(SP.hitsOn(fw, "SPELL_AURA_REMOVED", foe.guid), 0)
    end)
  end)
end

return function()
  test_an_aura_survives_a_reload_and_is_logged_when_it_ends()
  test_a_reload_drops_the_record_of_an_aura_that_had_run_out()
end
