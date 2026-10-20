-- Bug: inherits a template that does not exist.
local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  ns.panel = CreateFrame("Frame", nil, UIParent, "NoSuchTemplate")
end)
