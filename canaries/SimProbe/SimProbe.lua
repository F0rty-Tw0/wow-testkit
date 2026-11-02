-- SimProbe: logs the sim's events into SimProbeLog as { event, ... } records. Slices 3-5 append their event names to
-- SimProbe.EVENTS.
SimProbe = { EVENTS = { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" } }
SimProbeLog = {}

local frame = CreateFrame("Frame")
for _, event in ipairs(SimProbe.EVENTS) do
  frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
  SimProbeLog[#SimProbeLog + 1] = { event, ... }
end)
