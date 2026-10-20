-- Bug: passes nil where the unit token is required.
local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  ns.name = UnitName(nil)
end)
