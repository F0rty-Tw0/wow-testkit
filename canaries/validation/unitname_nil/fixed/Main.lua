-- Fixed: passes the unit token and leaves the defaulted second argument out.
local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  ns.health = UnitHealth("player")
end)
