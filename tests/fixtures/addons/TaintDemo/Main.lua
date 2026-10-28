-- Taint demo: a hidden secure panel and three slash commands that each make the taint log a line, the way a real addon
-- trips the client. /tdemo cast calls a protected function, /tdemo show calls Show on a protected frame (blocked in
-- combat), /tdemo taint overwrites a Blizzard global.
local panel = CreateFrame("Button", "TaintDemoPanel", UIParent, "SecureActionButtonTemplate")
panel:SetSize(160, 40)
panel:SetPoint("CENTER")
local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.1, 0.3, 0.5, 1)
local label = panel:CreateFontString("TaintDemoPanelLabel")
label:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
label:SetPoint("CENTER")
label:SetText("secure panel")
panel:Hide()

local events = CreateFrame("Frame", "TaintDemoEvents", UIParent)
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:SetScript("OnEvent", function(_, event, addon, name)
  print(event, addon, name)
end)

SLASH_TDEMO1 = "/tdemo"
SlashCmdList.TDEMO = function(msg)
  if msg == "cast" then
    CastSpellByName("Kit Strike")
  elseif msg == "show" then
    TaintDemoPanel:Show()
  elseif msg == "taint" then
    local orig = UnitName
    UnitName = function(...)
      return orig(...)
    end
    print("issecurevariable", issecurevariable("UnitName"))
  end
end
