local frame = CreateFrame("Frame", "SessionDemoFrame", UIParent)
frame:SetSize(200, 60)
frame:SetPoint("CENTER")
local text = frame:CreateFontString("SessionDemoText")
text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
text:SetPoint("CENTER")
text:SetText("idle")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", function(_, event)
  text:SetText("event:" .. event)
end)
SLASH_SDEMO1 = "/sdemo"
SlashCmdList.SDEMO = function(msg)
  if msg == "boom" then
    error("boom")
  end
  text:SetText("slash:" .. msg)
end
SessionDemoDB = SessionDemoDB or { runs = 0 }
SessionDemoDB.runs = SessionDemoDB.runs + 1
