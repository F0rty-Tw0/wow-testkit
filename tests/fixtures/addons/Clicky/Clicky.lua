-- Clicky: scenario fixture. A panel with a button, a check button and an edit box that log every click, hover
-- and typing event into ns.log as "<frame>:<event>".
local _, ns = ...

ns.log = {}

local function log(self, text)
  ns.log[#ns.log + 1] = self:GetName() .. ":" .. text
end

local function logHover(self)
  self:SetScript("OnEnter", function(frame, motion)
    log(frame, "enter:" .. tostring(motion))
  end)
  self:SetScript("OnLeave", function(frame, motion)
    log(frame, "leave:" .. tostring(motion))
  end)
end

local panel = CreateFrame("Frame", "ClickyPanel", UIParent)
panel:SetSize(200, 120)
panel:SetPoint("CENTER")

local button = CreateFrame("Button", "ClickyButton", panel)
button:SetSize(80, 24)
button:SetPoint("TOP")
button:RegisterForClicks("AnyUp")
button:SetScript("OnClick", function(self, mouseButton, down)
  log(self, "click:" .. mouseButton .. ":" .. tostring(down))
end)
logHover(button)

local check = CreateFrame("CheckButton", "ClickyCheck", panel)
check:SetSize(24, 24)
check:SetPoint("CENTER")
check:SetScript("OnClick", function(self)
  log(self, "click:checked=" .. tostring(self:GetChecked()))
end)
logHover(check)

local box = CreateFrame("EditBox", "ClickyBox", panel)
box:SetSize(120, 24)
box:SetPoint("BOTTOM")
box:SetScript("OnTextChanged", function(self, userInput)
  log(self, "text:" .. self:GetText() .. ":" .. tostring(userInput))
end)
box:SetScript("OnEnterPressed", function(self)
  log(self, "enter-pressed:" .. self:GetText())
end)
