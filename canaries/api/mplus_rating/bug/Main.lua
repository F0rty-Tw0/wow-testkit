-- Bug: calls a retail-only API on every flavor.
local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  ns.rating = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
end)
