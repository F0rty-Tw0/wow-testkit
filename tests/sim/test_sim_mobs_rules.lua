-- Sim mob rules a mutation sweep found unpinned: transitive social pull, a dummy's blindness, stun against chase and
-- facing, the group's engagement, and what a reload keeps of loot.
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local Group = require("combat_group")
local H = require("tests.helpers.session")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SimMobs = require("sim_mobs")

local CURSE = 900005

local function curse(w)
  w.mock.spells[CURSE] = { name = "Kit Curse", harmful = true } -- mutate, never replace, w.mock.spells
end

-- Player (0,-10). A (0,0) sees it. B (10,0): 11.1 reduced from the player, so asleep, 7 from A -> pulled. C (20,0): 17 from
-- A, 7 from B -> pulled only through B.
local function test_social_pull_is_transitive()
  SH.withSim("retail", function(w, s)
    local a = SimMobs.spawn(w, { pos = { x = 0, y = 0 } })
    local b = SimMobs.spawn(w, { pos = { x = 10, y = 0 } })
    local c = SimMobs.spawn(w, { pos = { x = 20, y = 0 } })
    local d = SimMobs.spawn(w, { pos = { x = 40, y = 0 } })
    s:simStep(0.1)
    A.same({ a.mobState, b.mobState, c.mobState, d.mobState }, { "engaged", "engaged", "engaged", "idle" })
  end)
end

local function test_a_dummy_does_not_wake_on_sight()
  SH.withSim("retail", function(w, s)
    local dummy = SimMobs.spawn(w, { pos = { x = 0, y = 0 }, ai = false })
    local regen = SH.record(w, { "PLAYER_REGEN_DISABLED" })
    s:simStep(1)
    A.same({ dummy.mobState, #regen }, { "idle", 0 })
  end)
end

local function test_a_stunned_mob_neither_chases_nor_turns_but_a_rooted_one_turns()
  SH.withSim("retail", function(w, s, player)
    curse(w)
    local stunned = SimMobs.spawn(w, { pos = { x = 0, y = 0 } })
    local rooted = SimMobs.spawn(w, { pos = { x = 0, y = 30 } })
    Auras.apply(w, stunned, { spellID = CURSE, stun = true })
    Auras.apply(w, rooted, { spellID = CURSE, root = true })
    local facing = { stunned = stunned.facing, rooted = rooted.facing }
    Resolve.damage(w, player, stunned, { amount = 1 })
    Resolve.damage(w, player, rooted, { amount = 1 })
    s:place(15, -10) -- the mobs would now turn toward the east
    s:simStep(1)
    A.same({ stunned.pos.y, stunned.facing }, { 0, facing.stunned })
    A.same({ rooted.pos.y, rooted.facing ~= facing.rooted }, { 30, true })
  end)
end

local function test_an_aggro_engages_the_group_with_the_mob()
  SH.withSim("retail", function(w, s, player)
    local ann = Actors.add(w, { kind = "player", name = "Ann", pos = { x = 30, y = 30 } })
    Group.set(w, { player, ann })
    local mob = SimMobs.spawn(w, { pos = { x = 0, y = 0 } })
    s:simStep(0.1)
    A.same({ mob.foes[ann.guid], ann.affectingCombat, mob.foes[player.guid] }, { true, true, true })
  end)
end

local function test_loot_survives_a_reload_including_false_on_a_friendly_mob()
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    local boar = SimMobs.spawn(sess.w, { pos = { x = 0, y = 30 }, loot = { copper = 12 } })
    local friend = SimMobs.spawn(sess.w, { pos = { x = 5, y = 30 }, hostile = false, loot = false })
    local plain = SimMobs.spawn(sess.w, { pos = { x = 10, y = 30 }, hostile = false })
    SH.reloaded(sess, function(fresh)
      local function loot(mob)
        return Actors.get(fresh.w, mob.guid).loot
      end
      A.same({ loot(boar), loot(friend), loot(plain) }, { { copper = 12 }, false, nil })
    end)
  end)
end

return function()
  test_social_pull_is_transitive()
  test_a_dummy_does_not_wake_on_sight()
  test_a_stunned_mob_neither_chases_nor_turns_but_a_rooted_one_turns()
  test_an_aggro_engages_the_group_with_the_mob()
  test_loot_survives_a_reload_including_false_on_a_friendly_mob()
end
