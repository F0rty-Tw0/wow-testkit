-- UIDropDownMenu fake state: the menu level Initialize hides from, empty and failing toggles, and checked values.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function addItem(spec)
  local info = _G.UIDropDownMenu_CreateInfo()
  info.text = spec[1]
  for k, v in pairs(spec[2] or {}) do
    info[k] = v
  end
  _G.UIDropDownMenu_AddButton(info, 1)
end

-- A dropdown whose init adds items (level 1) or menuList's items (level 2+); specs are { text, infoFields }.
local function newDropdown(items, name)
  local frame = _G.CreateFrame("Frame", name or "StateDD", _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(frame, function(_, level, menuList)
    for _, spec in ipairs((level or 1) > 1 and menuList or items) do
      addItem(spec)
    end
  end, "MENU")
  return frame
end

local function openMenu(items)
  local frame = newDropdown(items)
  _G.ToggleDropDownMenu(1, nil, frame)
  return frame
end

-- Mainline UIDropDownMenu.lua:41-65: on the open menu's frame the helper hides lists from UIDROPDOWNMENU_MENU_LEVEL
-- (1 after a level-1 Toggle), so Toggle finds list 1 hidden and opens it again.
local function test_initialize_then_toggle_on_click_keeps_the_menu_open()
  withFrameXML("retail", function(w)
    local frame = _G.CreateFrame("Frame", "ClickDD", _G.UIParent, "UIDropDownMenuTemplate")
    local button = _G.CreateFrame("Button", "ClickDDButton", _G.UIParent)
    button:SetScript("OnClick", function()
      _G.UIDropDownMenu_Initialize(frame, function()
        addItem({ "One" })
      end, "MENU")
      _G.ToggleDropDownMenu(1, nil, frame)
    end)
    Input.click(w, button, "LeftButton")
    Input.click(w, button, "LeftButton")
    A.eq(#w.menus, 1)
    A.eq(w.menus[1].owner, frame)
    A.eq(_G.DropDownList1:IsShown(), true)
  end)
end

-- Entering More toggles level 2, so the open menu's Initialize hides list 2 and deeper and keeps list 1.
local function test_initialize_on_the_open_menu_hides_from_the_last_toggled_level()
  withFrameXML("retail", function(w)
    local frame = openMenu({ { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    Input.enter(w, w.menus[1].entries[1].frame)
    _G.UIDropDownMenu_Initialize(frame, nil, "MENU")
    A.eq(#w.menus, 1)
    A.eq(_G.DropDownList1:IsShown(), true)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

-- Mainline :43-45: Initialize on another frame resets the menu level to 1 first, so every list hides even after a
-- level-2 Toggle.
local function test_initialize_on_another_frame_after_a_submenu_hides_every_list()
  withFrameXML("retail", function(w)
    openMenu({ { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    Input.enter(w, w.menus[1].entries[1].frame)
    A.eq(#w.menus, 2)
    local other = _G.CreateFrame("Frame", "OtherDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(other, nil, "MENU")
    A.eq(#w.menus, 0)
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

-- Mainline :1193-1197, Classic :1133-1136: a list with no buttons is not shown.
local function test_toggle_with_no_entries_opens_nothing()
  withFrameXML("retail", function(w)
    openMenu({})
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

local function test_entering_an_arrow_entry_whose_submenu_is_empty_opens_nothing()
  withFrameXML("retail", function(w)
    openMenu({ { "Empty", { hasArrow = true, menuList = {} } } })
    Input.enter(w, w.menus[1].entries[1].frame)
    A.eq(#w.menus, 1)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

-- Mainline :1086 (Classic :1025-1026) hides the toggled list before init runs, so an init error leaves it closed.
local function test_toggle_whose_init_errors_leaves_the_old_submenu_closed()
  withFrameXML("retail", function(w)
    local frame = _G.CreateFrame("Frame", "FailDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(frame, function(_, level, menuList)
      if level == 2 and menuList == "boom" then
        error("submenu boom")
      end
      local specs = level == 2 and menuList
        or { { "Good", { hasArrow = true, menuList = { { "Nested" } } } }, { "Bad", { hasArrow = true, menuList = "boom" } } }
      for _, spec in ipairs(specs) do
        addItem(spec)
      end
    end, "MENU")
    _G.ToggleDropDownMenu(1, nil, frame)
    Input.enter(w, w.menus[1].entries[1].frame)
    A.eq(#w.menus, 2)
    pcall(Input.enter, w, w.menus[1].entries[2].frame)
    A.eq(#w.menus, 1)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

local function test_function_checked_returning_false_or_nil_reads_false()
  withFrameXML("retail", function(w)
    openMenu({
      { "F", {
        isNotRadio = true,
        checked = function()
          return false
        end,
      } },
      { "N", { isNotRadio = true, checked = function() end } },
    })
    A.eq(w.menus[1].entries[1].checked, false)
    A.eq(w.menus[1].entries[2].checked, false)
  end)
end

local function test_function_checked_error_is_recorded_and_reads_false()
  withFrameXML("retail", function(w)
    openMenu({ { "E", {
      isNotRadio = true,
      checked = function()
        error("checked boom")
      end,
    } } })
    A.eq(w.menus[1].entries[1].checked, false)
    A.eq(#w.errors, 1)
    A.contains(tostring(w.errors[1].message), "checked boom")
  end)
end

-- Mainline :999-1042, Classic :940-983: the flipped value is stored back on the button, so a second click flips it again.
local function test_keep_shown_on_click_checkbox_flips_on_every_click()
  withFrameXML("retail", function(w)
    local got = {}
    openMenu({
      {
        "Toggle",
        {
          isNotRadio = true,
          checked = true,
          keepShownOnClick = true,
          func = function(_, _, _, checked)
            got[#got + 1] = checked
          end,
        },
      },
    })
    local frame = w.menus[1].entries[1].frame
    Input.click(w, frame, "LeftButton")
    Input.click(w, frame, "LeftButton")
    A.same(got, { false, true })
  end)
end

return function()
  test_function_checked_returning_false_or_nil_reads_false()
  test_function_checked_error_is_recorded_and_reads_false()
  test_keep_shown_on_click_checkbox_flips_on_every_click()
  test_toggle_whose_init_errors_leaves_the_old_submenu_closed()
  test_initialize_then_toggle_on_click_keeps_the_menu_open()
  test_initialize_on_the_open_menu_hides_from_the_last_toggled_level()
  test_initialize_on_another_frame_after_a_submenu_hides_every_list()
  test_toggle_with_no_entries_opens_nothing()
  test_entering_an_arrow_entry_whose_submenu_is_empty_opens_nothing()
end
