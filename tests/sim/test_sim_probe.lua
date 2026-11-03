-- SimProbe addon (AC2): it logs the sim's events into SimProbeLog, so the kit's own world is checked through an addon
-- that registers for them like any other. UNIT_DIED and PARTY_KILL are combat log subevents (retail refuses CLEU to
-- addons), so test_sim_e2e.lua reads those from w.combat.log.
local A = require("assert")
local H = require("tests.helpers.sim")
local LH = require("tests.helpers.sim_loot")
local Scenario = require("scenario")
local SH = require("tests.helpers.sim_combat")
local SimTarget = require("sim_target")

-- Runs fn(s) on a logged-in SimProbe sim world and returns the names of the events it logged; the world is always destroyed.
local function probeNames(flavor, fn)
  local s = Scenario.new({ addon = "SimProbe", root = "canaries/SimProbe", flavor = flavor, sim = {} })
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

return function()
  test_the_probe_logs_the_moving_events()
  test_the_probe_logs_the_melee_kill_in_order()
  test_the_probe_logs_the_loot_in_order()
end
