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

-- Menu API context menu: right-click ClickyMenuApiButton. A title, a button, a submenu, a checkbox that keeps
-- the menu open, two radios, a divider and a disabled entry; plus a hook on Blizzard's friend menu.
local menuApi = { checked = false, radio = "A", picks = {} }
ns.menuApi = menuApi

local function pickLogger(name)
  return function()
    menuApi.picks[#menuApi.picks + 1] = name
  end
end

if MenuUtil and MenuUtil.CreateContextMenu then
  local menuButton = CreateFrame("Button", "ClickyMenuApiButton", UIParent)
  menuButton:SetSize(24, 24)
  menuButton:SetPoint("TOPLEFT")
  menuButton:RegisterForClicks("AnyUp")
  menuButton:SetScript("OnClick", function(self, mouseButton)
    if mouseButton ~= "RightButton" then
      return
    end
    MenuUtil.CreateContextMenu(self, function(_, root)
      root:CreateTitle("Clicky")
      root:CreateButton("Plain", pickLogger("Plain"))
      root:CreateButton("More"):CreateButton("Deep", pickLogger("Deep"))
      root:CreateCheckbox("Check", function()
        return menuApi.checked
      end, function()
        menuApi.checked = not menuApi.checked -- no return: a checkbox defaults to MenuResponse.Refresh
      end)
      root:CreateRadio("Radio A", function()
        return menuApi.radio == "A"
      end, function()
        menuApi.radio = "A"
      end)
      root:CreateRadio("Radio B", function()
        return menuApi.radio == "B"
      end, function()
        menuApi.radio = "B"
      end)
      root:CreateDivider()
      root:CreateButton("Off", pickLogger("Off")):SetEnabled(false)
    end)
  end)
end

if Menu and Menu.ModifyMenu then
  Menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, contextData)
    if contextData and contextData.clicky then
      root:CreateDivider()
      root:CreateTitle("Clicky")
      root:CreateButton("Clicky action", pickLogger("Clicky action"))
    end
  end)
end
