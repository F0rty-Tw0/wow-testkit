-- Clicky UIDropDownMenu: a button that opens a menu with every entry kind and a nested level; picks go to ns.picks.
local _, ns = ...

if not UIDropDownMenu_Initialize then
  return
end

ns.picks = {}

local function record(name)
  return function(_, _, _, checked)
    local suffix = name == "Show" and ":" .. tostring(checked) or ""
    ns.picks[#ns.picks + 1] = name .. suffix
  end
end

local function add(level, text, fields)
  local info = UIDropDownMenu_CreateInfo()
  info.text = text
  for key, value in pairs(fields) do
    info[key] = value
  end
  UIDropDownMenu_AddButton(info, level)
end

local function addLevelOne()
  add(1, "|cff00ff00Clicky|r", { isTitle = true, notCheckable = true })
  add(1, "Open", { notCheckable = true, func = record("Open") })
  add(1, "Show", { isNotRadio = true, checked = true, func = record("Show") })
  add(1, "Mode A", { checked = true, func = record("Mode A") })
  add(1, "Mode B", { func = record("Mode B") })
  add(1, nil, { isTitle = true, notCheckable = true })
  add(1, "Locked", { notCheckable = true, disabled = true })
  add(1, "More", { notCheckable = true, hasArrow = true, value = "more", menuList = { "Nested" } })
end

local function init(_, level, menuList)
  if level == 2 then
    add(2, menuList[1], { notCheckable = true, func = record(menuList[1]) })
    return
  end
  addLevelOne()
end

local dropdown = CreateFrame("Frame", "ClickyDropDown", UIParent, "UIDropDownMenuTemplate")
UIDropDownMenu_Initialize(dropdown, init, "MENU")

local menuButton = CreateFrame("Button", "ClickyMenuButton", UIParent)
menuButton:SetSize(80, 24)
menuButton:SetPoint("TOPLEFT")
menuButton:RegisterForClicks("AnyUp")
menuButton:SetScript("OnClick", function(self)
  ToggleDropDownMenu(1, nil, dropdown, self, 0, 0)
end)
