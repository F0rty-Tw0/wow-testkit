-- UIDropDownMenu fake: Toggle and a hasArrow entry open, replace and close levels.
-- Split from test_dropdown.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function addItem(spec, level)
  local info = _G.UIDropDownMenu_CreateInfo()
  info.text = spec[1]
  for k, v in pairs(spec[2] or {}) do
    info[k] = v
  end
  _G.UIDropDownMenu_AddButton(info, level)
end

-- A dropdown whose init adds items (level 1) or menuList's items (level 2); specs are { text, infoFields }.
local function newDropdown(items, name)
  local frame = _G.CreateFrame("Frame", name or "TestDD", _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(frame, function(_, level, menuList)
    for _, spec in ipairs(level == 2 and menuList or items) do
      addItem(spec, level)
    end
  end, "MENU")
  return frame
end

local function openMenu(items)
  local frame = newDropdown(items)
  _G.ToggleDropDownMenu(1, nil, frame)
  return frame
end

local function texts(w, depth)
  local out = {}
  for i, e in ipairs(w.menus[depth or 1].entries) do
    out[i] = e.text
  end
  return out
end

local function test_toggle_opens_level_one_owned_by_the_frame()
  withFrameXML("retail", function(w)
    local frame = openMenu({ { "One" } })
    A.eq(w.menus[1].owner, frame)
    A.eq(w.menus[1].namePrefix, "DropDownList1")
    A.eq(_G.DropDownList1:IsShown(), true)
  end)
end

local function test_toggle_again_on_the_owning_frame_closes_the_menu()
  withFrameXML("retail", function(w)
    local frame = openMenu({ { "One" } })
    _G.ToggleDropDownMenu(1, nil, frame)
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

local function test_toggle_on_another_frame_replaces_the_open_menu()
  withFrameXML("retail", function(w)
    openMenu({ { "One" } })
    local other = newDropdown({ { "Other" } }, "OtherDD")
    _G.ToggleDropDownMenu(1, nil, other)
    A.eq(#w.menus, 1)
    A.eq(w.menus[1].owner, other)
    A.same(texts(w), { "Other" })
  end)
end

local function test_toggle_without_a_frame_uses_the_owner_of_level_one()
  withFrameXML("retail", function(w)
    local frame = openMenu({ { "More", { hasArrow = true } } })
    _G.ToggleDropDownMenu(2, "v", nil, nil, nil, nil, { { "Nested" } })
    A.eq(#w.menus, 2)
    A.eq(w.menus[2].owner, frame)
    A.same(texts(w, 2), { "Nested" })
  end)
end

local function test_toggle_on_a_frame_without_initialize_errors()
  withFrameXML("retail", function()
    local frame = _G.CreateFrame("Frame", "BareDD", _G.UIParent, "UIDropDownMenuTemplate")
    A.errors(function()
      _G.ToggleDropDownMenu(1, nil, frame)
    end, "UIDropDownMenu_Initialize")
  end)
end

local function test_entering_has_arrow_entry_calls_toggle_with_value_menu_list_and_entry()
  withFrameXML("retail", function(w)
    local menuList = { { "Nested" } }
    openMenu({ { "More", { hasArrow = true, value = "v", menuList = menuList } } })
    local real, got = _G.ToggleDropDownMenu, nil
    _G.ToggleDropDownMenu = function(...)
      got = { n = select("#", ...), ... }
      return real(...)
    end
    local entry = w.menus[1].entries[1].frame
    Input.enter(w, entry)
    A.eq(got.n, 10) -- Mainline passes menuList, the entry frame, nil, menuListDisplayMode (UIDropDownMenu.lua:187)
    A.eq(got[1], 2)
    A.eq(got[2], "v")
    A.eq(got[3], nil)
    A.eq(got[7], menuList)
    A.eq(got[8], entry)
  end)
end

local function test_entering_has_arrow_entry_without_value_passes_its_text()
  withFrameXML("vanilla", function(w)
    openMenu({ { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    local real, got = _G.ToggleDropDownMenu, nil
    _G.ToggleDropDownMenu = function(...)
      got = { n = select("#", ...), ... }
      return real(...)
    end
    Input.enter(w, w.menus[1].entries[1].frame)
    A.eq(got.n, 8) -- Classic stops at the entry frame (UIDropDownMenu.lua:214)
    A.eq(got[2], "More")
  end)
end

local function test_entering_has_arrow_entry_opens_level_two_under_that_entry()
  withFrameXML("retail", function(w)
    openMenu({ { "A" }, { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    Input.enter(w, w.menus[1].entries[2].frame)
    A.eq(#w.menus, 2)
    A.eq(w.menus[2].parentIndex, 2)
    A.same(texts(w, 2), { "Nested" })
  end)
end

local function test_entering_the_same_entry_again_keeps_its_submenu_open()
  withFrameXML("retail", function(w)
    openMenu({ { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    local frame = w.menus[1].entries[1].frame
    Input.enter(w, frame)
    local sub = w.menus[2]
    Input.enter(w, frame)
    A.eq(#w.menus, 2)
    A.eq(w.menus[2], sub)
  end)
end

local function test_close_drop_down_menus_closes_from_the_given_level()
  withFrameXML("retail", function(w)
    openMenu({ { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    Input.enter(w, w.menus[1].entries[1].frame)
    _G.CloseDropDownMenus(2)
    A.eq(#w.menus, 1)
    _G.CloseDropDownMenus()
    A.same(w.menus, {})
  end)
end

return function()
  test_toggle_opens_level_one_owned_by_the_frame()
  test_toggle_again_on_the_owning_frame_closes_the_menu()
  test_toggle_on_another_frame_replaces_the_open_menu()
  test_toggle_without_a_frame_uses_the_owner_of_level_one()
  test_toggle_on_a_frame_without_initialize_errors()
  test_entering_has_arrow_entry_calls_toggle_with_value_menu_list_and_entry()
  test_entering_has_arrow_entry_without_value_passes_its_text()
  test_entering_has_arrow_entry_opens_level_two_under_that_entry()
  test_entering_the_same_entry_again_keeps_its_submenu_open()
  test_close_drop_down_menus_closes_from_the_given_level()
end
