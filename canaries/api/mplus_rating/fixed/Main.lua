-- Fixed: calls the retail-only API only where it exists.
local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  if C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
    ns.rating = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
  end
end)
