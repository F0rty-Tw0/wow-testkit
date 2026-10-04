-- Hover: scenario fixture. Counts logins, greets the mouseover unit on the tooltip, and errors at login when
-- HoverDB.boom is set.
local _, ns = ...

ns.logins = 0

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  if HoverDB and HoverDB.boom then
    error("boom")
  end
  ns.logins = ns.logins + 1
end)

local function greet()
  GameTooltip:AddLine("Hi " .. UnitName("mouseover"))
end

if TooltipDataProcessor then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, greet)
else
  GameTooltip:HookScript("OnTooltipSetUnit", greet)
end
