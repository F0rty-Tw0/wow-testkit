local text = _G.SessionDemoText

-- A solid background, so the viewer draws the widget.
local function fill(frame, r, g, b)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(r, g, b, 1)
end

local button = CreateFrame("Button", "SessionDemoButton", UIParent)
button:SetSize(120, 24)
button:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
button:RegisterForClicks("AnyUp")
fill(button, 0.5, 0.1, 0.1)
local label = button:CreateFontString("SessionDemoButtonLabel")
label:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
label:SetPoint("CENTER")
label:SetText("Click")
local clicks = 0
button:SetScript("OnClick", function()
  clicks = clicks + 1
  print("button clicked", clicks)
  text:SetText("clicked " .. clicks)
end)
button:SetScript("OnEnter", function()
  text:SetText("hover")
end)

local box = CreateFrame("EditBox", "SessionDemoBox", UIParent)
box:SetSize(160, 24)
box:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
fill(box, 0.15, 0.15, 0.2)
box:SetScript("OnEnterPressed", function(self)
  text:SetText("entered:" .. self:GetText())
  self:ClearFocus()
end)
