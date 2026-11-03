-- Sim mobs: spawn defaults, the aggro rule (radius and the mob's front 180 degrees, or a fight already on), social pull,
-- chase to melee range, swing gating by range and stun, a dummy, and the reload.
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local Json = require("json")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local Sim = require("sim")
local SimMobs = require("sim_mobs")

local function near(a, b)
  return math.abs(a - b) < 1e-6
end

local function mobSwings(w, mob)
  local n = 0
  for _, e in ipairs(w.combat.log.entries) do
    if e[2] == "SWING_DAMAGE" and e[4] == mob.guid then
      n = n + 1
    end
  end

  return n
end

local function test_default_spawn_is_level_matched_20_yd_ahead_facing_the_player_and_idle()
  SH.withSim("retail", function(w, s, player)
    local mob = SimMobs.spawn(w, {})
    A.same({ mob.level, mob.healthMax, mob.isEnemy, mob.mobState }, { player.level, player.level * 10, true, "idle" })
    A.truthy(near(mob.pos.x, 0) and near(mob.pos.y, 10) and near(math.cos(mob.facing), -1))
    local regen = SH.record(w, { "PLAYER_REGEN_DISABLED" })
    s:simStep(2)
    A.same({ mob.mobState, mob.pos.y, #regen }, { "idle", 10, 0 }) -- reduced 17 > 10
  end)
end

local function test_pack_and_option_validation()
  SH.withSim("retail", function(w)
    local xs = {}
    for i, mob in ipairs(SimMobs.pack(w, 3)) do
      xs[i] = mob.pos.x
    end
    A.same(xs, { -3, 0, 3 })
    A.errors(function()
      SimMobs.spawn(w, { name = 5 })
    end, "name must be a string")
    A.errors(function()
      SimMobs.spawn(w, { pos = { x = "a", y = 0 } })
    end, "pos")
  end)
end

local function test_bad_options_raise_before_anything_is_added_and_without_a_file_path()
  SH.withSim("retail", function(w)
    local function refused(opts, needle)
      local message = A.errors(function()
        SimMobs.spawn(w, opts)
      end, needle)
      A.eq(string.find(message, ".lua:", 1, true), nil, message)
      A.eq(#w.combat.order, 1, needle) -- the player only
    end
    refused({ ai = { swing = "x" } }, "SimMobs.spawn: ai.swing must be a table")
    refused({ ai = { swing = { damage = 3 } } }, "SimMobs.spawn: ai.swing: a rule's every")
    refused({ ai = { swing = { every = 2, damage = "x" } } }, "SimMobs.spawn: ai.swing.damage must be a number")
    refused({ level = 0 }, "SimMobs.spawn: level must be a number above 0")
    refused({ health = -5 }, "SimMobs.spawn: health must be a number above 0")
    local message = A.errors(function()
      SimMobs.pack(w, 2, { name = 5 })
    end, "SimMobs.spawn: name must be a string")
    A.eq(string.find(message, ".lua:", 1, true), nil, message)
    A.eq(#w.combat.order, 1)
    A.eq(#SimMobs.pack(w, 1, { ai = false }), 1) -- a dummy is still allowed
  end)
end

-- Mob (0,0), player (0,-10): reduced 7 <= 10 and the player is in front of the mob.
local function test_aggro_chase_stop_in_range_then_swing_on_cadence()
  SH.withSim("retail", function(w, s)
    local mob = SimMobs.spawn(w, { pos = { x = 0, y = 0 } })
    local regen = SH.record(w, { "PLAYER_REGEN_DISABLED" })
    s:simStep(1)
    A.same({ mob.mobState, #regen, mobSwings(w, mob) }, { "engaged", 1, 0 })
    A.truthy(near(mob.pos.y, -2)) -- stops at centre 8 (reduced 5)
    s:simStep(1.5) -- first AI tick at ~2.02
    A.same({ mobSwings(w, mob), mob.swings, w.combat.log.entries[#w.combat.log.entries][12] }, { 1, 1, 3 })
    s:simStep(1.6) -- second tick at ~4.02
    A.eq(mob.swings, 2)
  end)
end

local function test_player_behind_the_mob_does_not_aggro_until_it_attacks()
  SH.withSim("retail", function(w, s, player)
    local mob = SimMobs.spawn(w, { pos = { x = 0, y = -18 } })
    mob.facing = math.pi -- faces south; the player is north of it
    s:simStep(3)
    A.eq(mob.mobState, "idle")
    Resolve.damage(w, player, mob, { amount = 1 })
    s:simStep(0.1)
    A.eq(mob.mobState, "engaged")
  end)
end

-- A (0,0) aggros. B (8,5): 14 reduced from the player, 6.43 from A -> joins. C (20,20): 25 from A -> stays.
local function test_social_pull_takes_mobs_within_8_yd_only()
  SH.withSim("retail", function(w, s)
    local a = SimMobs.spawn(w, { pos = { x = 0, y = 0 } })
    local b = SimMobs.spawn(w, { pos = { x = 8, y = 5 } })
    local c = SimMobs.spawn(w, { pos = { x = 20, y = 20 } })
    local regen = SH.record(w, { "PLAYER_REGEN_DISABLED" })
    s:simStep(0.1)
    A.same({ a.mobState, b.mobState, c.mobState, #regen }, { "engaged", "engaged", "idle", 1 })
  end)
end

local function test_root_stops_movement_only_and_stun_stops_swings()
  SH.withSim("retail", function(w, s)
    w.mock.spells[900005] = { name = "Kit Curse", harmful = true } -- mutate, never replace, w.mock.spells
    local mob = SimMobs.spawn(w, { pos = { x = 0, y = 0 } })
    local root = Auras.apply(w, mob, { spellID = 900005, root = true })
    s:simStep(3)
    A.same({ mob.mobState, mob.pos.y, mobSwings(w, mob) }, { "engaged", 0, 0 })
    Auras.remove(w, mob, root)
    s:simStep(1)
    A.truthy(near(mob.pos.y, -2))
  end)
  SH.withSim("retail", function(w, s)
    w.mock.spells[900005] = { name = "Kit Curse", harmful = true }
    local mob = SimMobs.spawn(w, { pos = { x = 0, y = -2 } }) -- already in melee range
    local stun = Auras.apply(w, mob, { spellID = 900005, stun = true })
    s:simStep(4)
    A.eq(mobSwings(w, mob), 0)
    Auras.remove(w, mob, stun)
    Auras.apply(w, mob, { spellID = 900005, root = true }) -- root alone does not stop a swing in range
    s:simStep(2.1)
    A.truthy(mobSwings(w, mob) >= 1)
  end)
end

local function test_dummy_never_chases_and_reset_removes_mobs()
  SH.withSim("retail", function(w, s, player)
    local dummy = SimMobs.spawn(w, { pos = { x = 0, y = 0 }, ai = false })
    s:simStep(3)
    A.same({ dummy.pos.y, mobSwings(w, dummy) }, { 0, 0 })
    local guid = dummy.guid
    Sim.reset(w)
    A.same({ Actors.get(w, guid), Actors.get(w, player.guid) ~= nil }, { nil, true })
  end)
end

-- The swing rule carries functions (gate, onSwing); the export must stay plain data.
local function test_the_export_keeps_the_swing_rule_plain()
  SH.withSim("retail", function(w)
    SimMobs.spawn(w, { pos = { x = 0, y = 0 } })
    local state = Sim.export(w)
    A.same(state.actors[1].ai, { swing = { every = 2, damage = 3 } })
    A.truthy(pcall(Json.encode, state), "Json.encode takes it")
  end)
end

-- Review Focus 2: a reload in combat keeps the engaged mob chasing and swinging.
local function test_engaged_mobs_survive_reload()
  local H = require("tests.helpers.session")
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    local mob = SimMobs.spawn(sess.w, { pos = { x = 0, y = 0 } })
    for _ = 1, 12 do
      sess:call("sim", { action = "step", seconds = 0.25 })
    end
    local guid, y, hp = mob.guid, mob.pos.y, mob.health
    SH.reloaded(sess, function(fresh)
      local m2 = Actors.get(fresh.w, guid)
      A.same({ m2.mobState, m2.pos.y, m2.health, m2.isEnemy }, { "engaged", y, hp, true })
      local before = m2.swings or 0
      for _ = 1, 10 do
        fresh:call("sim", { action = "step", seconds = 0.25 })
      end
      A.truthy((m2.swings or 0) > before)
    end)
  end)
end

return function()
  test_default_spawn_is_level_matched_20_yd_ahead_facing_the_player_and_idle()
  test_pack_and_option_validation()
  test_bad_options_raise_before_anything_is_added_and_without_a_file_path()
  test_aggro_chase_stop_in_range_then_swing_on_cadence()
  test_player_behind_the_mob_does_not_aggro_until_it_attacks()
  test_social_pull_takes_mobs_within_8_yd_only()
  test_root_stops_movement_only_and_stun_stops_swings()
  test_dummy_never_chases_and_reset_removes_mobs()
  test_the_export_keeps_the_swing_rule_plain()
  test_engaged_mobs_survive_reload()
end
