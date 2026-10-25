local frame = CreateFrame("Frame", "SessionDemoFrame", UIParent)
frame:SetSize(200, 60)
frame:SetPoint("CENTER")
local hidden = CreateFrame("Frame", "SessionDemoHidden", frame)
hidden:SetSize(10, 10)
hidden:SetPoint("TOPLEFT")
hidden:Hide()
local text = frame:CreateFontString("SessionDemoText")
text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
text:SetPoint("CENTER")
text:SetText("idle")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" then
    -- The client applies SavedVariables after the files run, so the count goes up here, not in the main chunk.
    if name == "SessionDemo" then
      SessionDemoDB = SessionDemoDB or { runs = 0 }
      SessionDemoDB.runs = SessionDemoDB.runs + 1
      self:UnregisterEvent("ADDON_LOADED")
    end
    return
  end
  text:SetText("event:" .. event)
end)
SLASH_SDEMO1 = "/sdemo"
SlashCmdList.SDEMO = function(msg)
  if msg == "boom" then
    error("boom")
  end
  print("slash", msg)
  text:SetText("slash:" .. msg)
end
