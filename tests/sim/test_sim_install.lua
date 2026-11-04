-- Sim install phase 1: the player's place, class and level, the world bounds and map, and the option checks.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.sim")
local Scenario = require("scenario")
local Sim = require("sim")
local SimBags = require("sim_bags")
local SimLoot = require("sim_loot")
local SimLootWindow = require("sim_loot_window")
local SimEffects = require("sim_effects")
local SimGround = require("sim_ground")
local SimMelee = require("sim_melee")
local SimMobs = require("sim_mobs")
local SimMove = require("sim_move")
local SimSpells = require("sim_spells")

local function test_install_places_the_player()
  H.each({}, function(w)
    local p = Actors.get(w, "player")
    A.eq(w.sim.player, p)
    A.same({ p.pos.x, p.pos.y, p.facing, p.level }, { 0, -10, 0, 10 })
  end)
end

local function test_default_class_is_a_warrior_with_rage_assumed()
  H.each({}, function(w)
    local name, file = _G.UnitClass("player")
    A.same({ name, file }, { "Warrior", "WARRIOR" })
    A.same({ w.sim.class, w.sim.level }, { "WARRIOR", 10 })
    A.same({ _G.UnitPower("player"), _G.UnitPowerMax("player") }, { 0, 100 })
  end)
end

local function test_world_state_fields_assumed()
  H.each({}, function(w)
    A.same(w.sim.bounds, { minX = -50, maxX = 50, minY = -50, maxY = 50 })
    A.same(w.sim.mapRect, { left = -50, top = 50, size = 100 })
    A.same({ w.sim.intents, w.sim.activity, w.sim.clock }, { {}, 0, { t0 = w.now, carry = 0 } })
    A.same(w.sim.hooks.frame, { SimMove.frame, SimMelee.step, SimMobs.step, SimLootWindow.walkAway, SimSpells.step, SimEffects.step, SimGround.step })
    A.same(
      w.sim.hooks.reset,
      { SimMove.stop, SimMelee.reset, SimBags.clear, SimLootWindow.close, SimLoot.reset, SimSpells.reset, SimEffects.reset, SimGround.stop }
    )
    A.truthy(w.sim.hooks.persist.melee) -- the units' own reload state; their tests cover it
    A.truthy(w.sim.hooks.persist.mobs)
    A.truthy(w.sim.hooks.persist.bags)
    A.truthy(w.sim.hooks.persist.loot)
    A.truthy(w.sim.hooks.persist.spells)
    A.truthy(w.sim.hooks.persist.effects)
    A.truthy(w.sim.hooks.persist.ground)
    A.eq(w.mock.zone.mapID, Sim.MAP_ID)
    A.same(w.mock.zone.position, { x = 0.5, y = 0.6 })
  end)
end

local function test_mage_at_level_20_assumed()
  H.withSim("retail", { class = "MAGE", level = 20 }, function(w)
    local p = Actors.get(w, "player")
    local name, file = _G.UnitClass("player")
    A.same({ name, file, _G.UnitLevel("player"), p.powerToken }, { "Mage", "MAGE", 20, "MANA" })
    A.same({ _G.UnitPower("player"), _G.UnitPowerMax("player") }, { 100, 100 })
    A.eq(p.powerType, _G.Enum.PowerType.Mana)
  end)
end

local function test_no_sim_leaves_the_kit_unchanged()
  local s = Scenario.new({ addon = "T", root = "T", flavor = "retail" })
  A.same({ s.w.sim, s.w.combat }, { nil, nil })
  s.w:destroy()
end

local function test_activity_counts_world_changes()
  H.withSim("retail", {}, function(w)
    local p = Actors.get(w, "player")
    Actors.setPos(w, p, 1, -10)
    Actors.setHealth(w, p, 50)
    A.eq(w.sim.activity, 2)
  end)
end

local function test_second_install_raises()
  H.withSim("retail", {}, function(w)
    A.errors(function()
      Sim.install(w, {})
    end, "already installed")
  end)
end

local function test_options_validate()
  A.errors(function()
    Sim.options({ class = "DRUID" })
  end, "class must be WARRIOR or MAGE")
  A.errors(function()
    Sim.options({ level = 0 })
  end, "level must be a whole number 1-100")
  A.errors(function()
    Sim.options({ level = 10.5 })
  end, "level must be a whole number 1-100")
  A.same(Sim.options(nil), { class = "WARRIOR", level = 10 })
  A.same(Sim.options(true), { class = "WARRIOR", level = 10 })
  A.same(Sim.options({ class = "MAGE", level = 100, twoPhase = true }), { class = "MAGE", level = 100, twoPhase = true })
end

return function()
  test_install_places_the_player()
  test_default_class_is_a_warrior_with_rage_assumed()
  test_world_state_fields_assumed()
  test_mage_at_level_20_assumed()
  test_no_sim_leaves_the_kit_unchanged()
  test_activity_counts_world_changes()
  test_second_install_raises()
  test_options_validate()
end
