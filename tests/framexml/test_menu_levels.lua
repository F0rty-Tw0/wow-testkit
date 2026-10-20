-- Menu API fake: entering entries and the submenu levels they keep or close. Split from test_menu.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function enter(w, depth, index)
  Input.enter(w, w.menus[depth].entries[index].frame)
end

local function noop() end

-- Level 1: 1 Leaf (no children), 2 Off (disabled, one child), 3 More (one child).
local function openThree()
  _G.MenuUtil.CreateContextMenu(nil, function(_, root)
    root:CreateButton("Leaf", noop)
    local off = root:CreateButton("Off")
    off:SetEnabled(false)
    off:CreateButton("Hidden", noop)
    root:CreateButton("More"):CreateButton("Deep", noop)
  end)
end

-- Menu.lua:2289-2291: an entry whose own submenu is not open collapses the deeper levels.
local function test_entering_a_leaf_closes_a_sibling_submenu()
  withFrameXML("retail", function(w)
    openThree()
    enter(w, 1, 3)
    A.eq(#w.menus, 2)
    enter(w, 1, 1)
    A.eq(#w.menus, 1)
  end)
end

-- Menu.lua:2293: a disabled Button opens no submenu, even with children.
local function test_entering_a_disabled_entry_with_children_opens_nothing()
  withFrameXML("retail", function(w)
    openThree()
    enter(w, 1, 2)
    A.eq(#w.menus, 1)
  end)
end

-- Menu.lua:2289-2293: the collapse does not depend on enabled, so a disabled entry closes another entry's submenu.
local function test_entering_a_disabled_entry_closes_a_sibling_submenu()
  withFrameXML("retail", function(w)
    openThree()
    enter(w, 1, 3)
    enter(w, 1, 2)
    A.eq(#w.menus, 1)
  end)
end

-- Menu.lua:2286-2296 (CheckForSubmenu): deeper levels collapse only when the entry's own submenu is not open; a
-- disabled Button then opens nothing. So re-entering a disabled entry whose submenu is open keeps that submenu.
local function test_entering_a_disabled_entry_whose_submenu_is_open_keeps_it()
  withFrameXML("retail", function(w)
    local flag = { on = true }
    _G.MenuUtil.CreateContextMenu(_G.CreateFrame("Frame", nil, _G.UIParent), function(_, root)
      local more = root:CreateButton("More")
      more:SetEnabled(function()
        return flag.on
      end)
      more:CreateCheckbox("Lock", function()
        return not flag.on
      end, function()
        flag.on = not flag.on
      end)
    end)
    enter(w, 1, 1)
    local sub = w.menus[2]
    -- Refresh from level 2 re-reads level 1 (Menu.lua:2259-2262): More is now disabled with its submenu open.
    Input.click(w, sub.entries[1].frame, "LeftButton")
    A.eq(w.menus[1].entries[1].enabled, false)
    enter(w, 1, 1)
    A.eq(#w.menus, 2)
    A.eq(w.menus[2], sub)
  end)
end

-- A dropdown's level-2 initialize that opens a Menu API menu leaves the dropdown level at depth 2 with the entered
-- entry's index as its parent (row M17's stack shape). Entering that Menu API entry must still open its own submenu.
local function test_entering_an_entry_replaces_another_menus_level_with_the_same_parent_index()
  withFrameXML("retail", function(w)
    local dd = _G.CreateFrame("Frame", "LevelsNestDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(dd, function(_, level)
      if level == 2 then
        _G.MenuUtil.CreateContextMenu(nil, function(_, root)
          root:CreateButton("M1", noop)
          root:CreateButton("M2"):CreateButton("M2a", noop)
        end)
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text = "DDsub"
        _G.UIDropDownMenu_AddButton(info, 2)
        return
      end
      for _, text in ipairs({ "D1", "D2" }) do
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text = text
        info.hasArrow = text == "D2"
        _G.UIDropDownMenu_AddButton(info, 1)
      end
    end)
    _G.ToggleDropDownMenu(1, nil, dd)
    enter(w, 1, 2)
    A.eq(w.menus[2].parentIndex, 2)
    A.eq(w.menus[2].state, nil)
    enter(w, 1, 2)
    A.eq(w.menus[2].state, w.menus[1].state)
    A.eq(w.menus[2].entries[1].text, "M2a")
  end)
end

-- Row M17 (assumed): the two menu systems share one stack, so opening either closes the other's open lists.
local function test_opening_either_menu_system_closes_the_other_assumed()
  withFrameXML("retail", function(w)
    local dd = _G.CreateFrame("Frame", "LevelsDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(dd, function()
      local info = _G.UIDropDownMenu_CreateInfo()
      info.text = "Drop"
      _G.UIDropDownMenu_AddButton(info, 1)
    end)
    _G.ToggleDropDownMenu(1, nil, dd)
    local menu = _G.MenuUtil.CreateContextMenu(nil, function(_, root)
      root:CreateButton("Menu", function() end)
    end)
    A.eq(_G.DropDownList1:IsShown(), false)
    A.eq(w.menus[1].frame, menu)
    _G.ToggleDropDownMenu(1, nil, dd)
    A.eq(menu:IsShown(), false)
    A.eq(w.menus[1].frame, _G.DropDownList1)
  end)
end

return function()
  test_entering_a_leaf_closes_a_sibling_submenu()
  test_entering_a_disabled_entry_with_children_opens_nothing()
  test_entering_a_disabled_entry_closes_a_sibling_submenu()
  test_entering_a_disabled_entry_whose_submenu_is_open_keeps_it()
  test_entering_an_entry_replaces_another_menus_level_with_the_same_parent_index()
  test_opening_either_menu_system_closes_the_other_assumed()
end
