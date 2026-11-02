-- SimProbe addon (AC2): it logs the sim's events into SimProbeLog, so the kit's own world is checked through an addon
-- that registers for them like any other.
local A = require("assert")
local H = require("tests.helpers.sim")
local Scenario = require("scenario")

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

return function()
  test_the_probe_logs_the_moving_events()
end
