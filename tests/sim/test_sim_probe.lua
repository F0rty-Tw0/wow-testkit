-- SimProbe addon (AC2): it logs the sim's events into SimProbeLog, so the kit's own world is checked through an addon
-- that registers for them like any other. UNIT_DIED and PARTY_KILL are combat log subevents (retail refuses CLEU to
-- addons), so test_sim_e2e.lua reads those from w.combat.log.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.sim")
local LH = require("tests.helpers.sim_loot")
local Scenario = require("scenario")
local SH = require("tests.helpers.sim_combat")
local SimMelee = require("sim_melee")
local SimMobs = require("sim_mobs")
local SimTarget = require("sim_target")

-- Runs fn(s) on a logged-in SimProbe sim world (sim options `sim`, default {}) and returns the names of the events it
-- logged; the world is always destroyed.
local function probeNames(flavor, fn, sim)
  local s = Scenario.new({ addon = "SimProbe", root = "canaries/SimProbe", flavor = flavor, sim = sim or {} })
  local ok, result = pcall(function()
    s:login()
    fn(s)

    return H.names(_G.SimProbeLog)
  end)
  s.w:destroy()
  if not ok then
    error(result, 0)
  end

  return result
end

local function test_the_probe_logs_the_moving_events()
  for _, flavor in ipairs(H.FLAVORS) do
    local names = probeNames(flavor, function(s)
      s:key("W", "down")
      s:simStep(0.5)
      s:key("W", "up")
      s:simStep(0.1)
    end)
    A.same(names, { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" })
  end
end

local function test_the_probe_logs_the_melee_kill_in_order()
  for _, flavor in ipairs(H.FLAVORS) do
    local names = probeNames(flavor, function(s)
      local mob = s:spawn({ health = 20 })
      s.w:run("blizzard", SimTarget.pointer, s.w, "enter", { guid = mob.guid })
      s:clickUnit(mob, "RightButton")
      SH.walkIntoMelee(s, mob)
      SH.fightUntilDead(s, mob)
      s:simStep(5.1)
    end)
    A.same(names, {
      "UPDATE_MOUSEOVER_UNIT",
      "PLAYER_TARGET_CHANGED",
      "PLAYER_STARTED_MOVING",
      "UI_ERROR_MESSAGE",
      "PLAYER_REGEN_DISABLED",
      "PLAYER_STOPPED_MOVING",
      "PLAYER_REGEN_ENABLED",
    }, flavor)
  end
end

local function test_the_probe_logs_the_loot_in_order()
  for _, flavor in ipairs(H.FLAVORS) do
    local names = probeNames(flavor, function(s)
      local mob = s:spawn({ health = 1 })
      s:place(mob.pos.x, mob.pos.y - 1)
      s:clickUnit(mob, "RightButton")
      local guard = 0
      while not mob.isDead and guard < 900 do
        s:simStep(0.25)
        guard = guard + 1
      end
      s:clickUnit(mob, "RightButton")
      _G.LootSlot(1)
      _G.LootSlot(2)
      _G.LootSlot(3)
    end)
    A.same(LH.from(names, "LOOT_READY"), {
      "LOOT_READY",
      "LOOT_OPENED",
      "LOOT_SLOT_CLEARED",
      "ITEM_PUSH",
      "BAG_UPDATE",
      "BAG_UPDATE_DELAYED",
      "CHAT_MSG_LOOT",
      "LOOT_SLOT_CLEARED",
      "ITEM_PUSH",
      "BAG_UPDATE",
      "BAG_UPDATE_DELAYED",
      "CHAT_MSG_LOOT",
      "LOOT_SLOT_CLEARED",
      "LOOT_CLOSED",
    }, flavor)
  end
end

-- The indexes at which each of events first shows in names (nil for an event never logged).
local function firstIndexes(names, events)
  local at = {}
  for _, event in ipairs(events) do
    for i, name in ipairs(names) do
      if name == event and not at[event] then
        at[event] = i
      end
    end
  end

  return at
end

local function test_the_probe_logs_a_fireball_start_cooldown_and_success()
  for _, flavor in ipairs(H.FLAVORS) do
    local names = probeNames(flavor, function(s)
      local foe = SH.foe(s.w, 0, 10)
      Actors.setTarget(s.w, s.w.sim.player, foe)
      _G.UseAction(1)
      s:simStep(4)
    end, { class = "MAGE" })
    local at = firstIndexes(names, { "UNIT_SPELLCAST_START", "ACTIONBAR_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SUCCEEDED" })
    A.eq(at.UNIT_SPELLCAST_START ~= nil and at.UNIT_SPELLCAST_START < at.ACTIONBAR_UPDATE_COOLDOWN, true, flavor .. " " .. table.concat(names, ","))
    A.eq(at.ACTIONBAR_UPDATE_COOLDOWN ~= nil and at.UNIT_SPELLCAST_SUCCEEDED ~= nil, true, flavor)
  end
end

local function test_the_probe_logs_the_overpower_glow_show_before_hide_on_tbc()
  local names = probeNames("tbc", function(s)
    local dummy = SimMobs.spawn(s.w, { pos = { x = 0, y = -9 }, health = 100000, ai = false })
    Actors.setTarget(s.w, s.w.sim.player, dummy)
    SimMelee.start(s.w)
    local guard = 0
    while not _G.C_SpellActivationOverlay.IsSpellOverlayed(7384) and guard < 80 do
      s:simStep(0.5)
      guard = guard + 1
    end
    SimMelee.stop(s.w)
    s:simStep(5.5)
  end, { class = "WARRIOR" })
  local at = firstIndexes(names, { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" })
  local show, hide = at.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW, at.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE
  A.eq(show ~= nil and hide ~= nil and show < hide, true, table.concat(names, ","))
end

return function()
  test_the_probe_logs_a_fireball_start_cooldown_and_success()
  test_the_probe_logs_the_overpower_glow_show_before_hide_on_tbc()
  test_the_probe_logs_the_moving_events()
  test_the_probe_logs_the_melee_kill_in_order()
  test_the_probe_logs_the_loot_in_order()
end
