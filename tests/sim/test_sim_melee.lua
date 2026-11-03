local A = require("assert")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SimMelee = require("sim_melee")
local SimTarget = require("sim_target")

local function swings(w, player) -- amounts of the player's SWING_DAMAGE lines ([12] = amount)
  local out = {}
  for _, e in ipairs(w.combat.log.entries) do
    if e[2] == "SWING_DAMAGE" and e[4] == player.guid then
      out[#out + 1] = e[12]
    end
  end
  return out
end

local function engageAt(w, y, extra) -- y=-2: centre 8, reduced 5, in front
  local foe = SH.foe(w, 0, y, extra or { health = 1000, healthMax = 1000 })
  SimTarget.target(w, foe)
  return foe
end

local function test_cadence_and_damage_cycle_per_class()
  for class, kit in pairs(SimMelee.KIT) do
    SH.withSim("retail", function(w, s, player)
      player.classFile = class
      local foe = engageAt(w, -2)
      local regen = SH.record(w, { "PLAYER_REGEN_DISABLED" })
      A.eq(SimMelee.start(w), true)
      s:simStep(kit.speed - 0.1)
      A.eq(player.swings, 1, class)
      s:simStep(0.2)
      A.eq(player.swings, 2, class)
      s:simStep(kit.speed)
      A.same({ player.swings, swings(w, player) }, { 3, { kit.min, kit.min + 1, kit.min + 2 } }, class)
      A.same({ foe.health, #regen }, { 1000 - (3 * kit.min + 3), 1 }, class)
    end)
  end
end

local function test_out_of_range_errors_once_then_swings_when_in_range()
  SH.withSim("retail", function(w, s, player)
    engageAt(w, 10) -- centre 20 -> 17
    local errors = SH.record(w, { "UI_ERROR_MESSAGE" })
    SimMelee.start(w)
    s:simStep(0.5)
    A.same({ #errors, errors[1][4], #swings(w, player) }, { 1, _G.ERR_BADATTACKPOS, 0 })
    s:place(0, 2) -- centre 8 -> 5
    s:simStep(0.1)
    A.same({ #swings(w, player), #errors }, { 1, 1 })
  end)
end

local function test_range_edge_is_inclusive()
  SH.withSim("retail", function(w, s, player)
    local foe = engageAt(w, -2)
    SimMelee.start(w)
    s:simStep(0.1)
    A.eq(#swings(w, player), 1)
    foe.pos.y = -1.9 -- reduced 5.1
    s:simStep(3)
    A.eq(#swings(w, player), 1)
  end)
end

local function test_wrong_facing_errors_then_swings_after_turning()
  SH.withSim("retail", function(w, s, player)
    engageAt(w, -18) -- reduced 5 but behind the north-facing player
    local errors = SH.record(w, { "UI_ERROR_MESSAGE" })
    SimMelee.start(w)
    s:simStep(0.5)
    A.same({ #errors, errors[1][4], #swings(w, player) }, { 1, _G.ERR_BADATTACKFACING, 0 })
    s:face(math.pi)
    s:simStep(0.1)
    A.eq(#swings(w, player), 1)
  end)
end

local function test_attack_stops_on_death_clear_retarget_and_despawn()
  local function stopsWhen(act)
    SH.withSim("retail", function(w, s)
      local foe = engageAt(w, -2)
      SimMelee.start(w)
      A.eq(w.sim.melee.on, true)
      act(w, foe)
      s:simStep(0.1)
      A.eq(w.sim.melee.on, false)
    end)
  end
  stopsWhen(function(w, foe)
    Resolve.kill(w, foe)
  end)
  stopsWhen(function()
    _G.ClearTarget()
  end)
  stopsWhen(function(w)
    SimTarget.target(w, SH.foe(w, 5, 5))
  end)
  stopsWhen(function(w, foe)
    require("combat_actors").remove(w, foe)
  end)
end

local function test_attack_survives_a_reload()
  local H = require("tests.helpers.session")
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    local foe = engageAt(sess.w, -2)
    SimMelee.start(sess.w)
    sess:call("sim", { action = "step", seconds = 0.1 })
    local guid, hp = foe.guid, foe.health
    SH.reloaded(sess, function(fresh)
      A.same({ fresh.w.sim.melee.on, fresh.w.sim.melee.targetGuid }, { true, guid })
      local function health()
        return require("combat_actors").get(fresh.w, guid).health
      end
      for _ = 1, 3 do
        fresh:call("sim", { action = "step", seconds = 0.25 })
      end
      A.eq(health(), hp) -- the 2.5 s left on the timer came back: no swing yet
      for _ = 1, 8 do
        fresh:call("sim", { action = "step", seconds = 0.25 })
      end
      A.truthy(health() < hp)
    end)
  end)
end

local function test_right_click_starts_the_attack_and_leaves_a_corpse_alone()
  SH.withSim("retail", function(w)
    local foe = SH.foe(w, 0, -2)
    SimTarget.interact(w, foe, "RightButton")
    A.same({ w.sim.melee.on, w.sim.melee.targetGuid }, { true, foe.guid })
    SimMelee.stop(w)
    Resolve.kill(w, foe)
    SimTarget.interact(w, foe, "RightButton")
    A.eq(w.sim.melee.on, false)
  end)
end

local function test_attack_fakes_exist_on_every_flavor_and_flip_the_attack()
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w)
      local foe = engageAt(w, -2)
      _G.StartAttack()
      A.eq(w.sim.melee.on, true, flavor)
      _G.StopAttack()
      A.eq(w.sim.melee.on, false, flavor)
      _G.AttackTarget()
      A.eq(w.sim.melee.on, true, flavor)
      _G.StopAttack()
      _G.StartAttack("target")
      A.same({ w.sim.melee.on, w.sim.melee.targetGuid }, { true, foe.guid }, flavor)
    end)
  end
end

local function test_attack_needs_a_living_enemy_target()
  SH.withSim("retail", function(w)
    A.eq(SimMelee.start(w), false)
    SimTarget.target(w, SH.foe(w, 0, -2, { hostile = false }))
    A.eq(SimMelee.start(w), false)
    A.eq(w.sim.melee.on, false)
  end)
end

local function test_error_strings_and_reset()
  SH.withSim("retail", function(w)
    A.same({ type(_G.ERR_BADATTACKPOS), type(_G.ERR_BADATTACKFACING) }, { "string", "string" })
    engageAt(w, -2)
    SimMelee.start(w)
    require("sim").reset(w)
    A.eq(w.sim.melee.on, false)
  end)
end

return function()
  test_cadence_and_damage_cycle_per_class()
  test_out_of_range_errors_once_then_swings_when_in_range()
  test_range_edge_is_inclusive()
  test_wrong_facing_errors_then_swings_after_turning()
  test_attack_stops_on_death_clear_retarget_and_despawn()
  test_attack_survives_a_reload()
  test_right_click_starts_the_attack_and_leaves_a_corpse_alone()
  test_attack_fakes_exist_on_every_flavor_and_flip_the_attack()
  test_attack_needs_a_living_enemy_target()
  test_error_strings_and_reset()
end
