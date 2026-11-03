-- SimProbe: logs the sim's events into SimProbeLog as { event, ... } records. Slices 3-5 append their event names to
-- SimProbe.EVENTS.
SimProbe = {
  EVENTS = {
    "PLAYER_STARTED_MOVING",
    "PLAYER_STOPPED_MOVING",
    "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "UI_ERROR_MESSAGE",
    "LOOT_READY",
    "LOOT_OPENED",
    "BAG_UPDATE",
    "BAG_UPDATE_DELAYED",
    "ITEM_PUSH",
    "CHAT_MSG_LOOT",
    "LOOT_SLOT_CLEARED",
    "LOOT_CLOSED",
  },
}
SimProbeLog = {}

local frame = CreateFrame("Frame")
for _, event in ipairs(SimProbe.EVENTS) do
  frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
  SimProbeLog[#SimProbeLog + 1] = { event, ... }
end)
