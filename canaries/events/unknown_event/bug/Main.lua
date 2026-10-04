-- Bug: registers a retail-only event on every flavor.
local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
ns.frame = frame
