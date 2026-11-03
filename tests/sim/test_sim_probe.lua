-- SimProbe addon (AC2): it logs the sim's events into SimProbeLog, so the kit's own world is checked through an addon
-- that registers for them like any other. UNIT_DIED and PARTY_KILL are combat log subevents (retail refuses CLEU to
-- addons), so test_sim_e2e.lua reads those from w.combat.log.
local A = require("assert")
local H = require("tests.helpers.sim")
local Scenario = require("scenario")
local SimMelee = require("sim_melee")
local SimTarget = require("sim_target")

local function test_the_probe_logs_the_moving_events()
  for _, flavor in ipairs(H.FLAVORS) do
    local s = Scenario.new({ addon = "SimProbe", root = "canaries/SimProbe", flavor = flavor, sim = {} })
    s:login()
    s:key("W", "down")
    s:simStep(0.5)
    s:key("W", "up")
    s:simStep(0.1)
    local names = H.names(_G.SimProbeLog)
    s.w:destroy()
    A.same(names, { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" })
  end
end

local function probeSession(flavor)
  local s = Scenario.new({ addon = "SimProbe", root = "canaries/SimProbe", flavor = flavor, sim = {} })
  s:login()

  return s
end

local function walkIntoMelee(s, mob)
  local guard = 0
  s:move({ forward = true })
  while not SimMelee.inRange(s.w.sim.player, mob) and guard < 300 do
    s:simStep(1 / 30)
    guard = guard + 1
  end
  s:move({})
end

local function killUntilCalm(s, mob)
  local guard = 0
  while not mob.isDead and guard < 600 do
    s:simStep(0.25)
    guard = guard + 1
  end
  s:simStep(5.1)
end

local function test_the_probe_logs_the_melee_kill_in_order()
  for _, flavor in ipairs(H.FLAVORS) do
    local s = probeSession(flavor)
    local mob = s:spawn({ health = 20 })
    s.w:run("blizzard", SimTarget.pointer, s.w, "enter", { guid = mob.guid })
    s:clickUnit(mob, "RightButton")
    walkIntoMelee(s, mob)
    killUntilCalm(s, mob)
    local names = H.names(_G.SimProbeLog)
    s.w:destroy()
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

return function()
  test_the_probe_logs_the_moving_events()
  test_the_probe_logs_the_melee_kill_in_order()
end
