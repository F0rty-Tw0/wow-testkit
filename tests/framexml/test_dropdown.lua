-- UIDropDownMenu fake: Initialize and AddButton build a level's entries; SetText, SetWidth and install.
local A = require("assert")
local H = require("tests.helpers.world")
local HF = require("tests.helpers.framexml")
local Input = require("input")
local Dropdown = require("framexml.fakes.dropdown")

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

local function test_initialize_calls_init_once_with_the_given_level_and_opens_nothing()
  withFrameXML("retail", function(w)
    local calls, menuList = {}, { "x" }
    local frame = _G.CreateFrame("Frame", "InitDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(frame, function(self, level, list)
      calls[#calls + 1] = { self, level, list }
      addItem({ "One" })
    end, "MENU", nil, menuList)
    A.eq(#calls, 1)
    A.eq(calls[1][1], frame)
    A.eq(calls[1][2], nil) -- level passes through unchanged (Mainline UIDropDownMenu.lua:83-86)
    A.eq(calls[1][3], menuList)
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

local function test_initialize_stores_init_display_mode_and_menu_list()
  withFrameXML("retail", function()
    local frame = _G.CreateFrame("Frame", "StoreDD", _G.UIParent, "UIDropDownMenuTemplate")
    local init, list = function() end, { "a" }
    _G.UIDropDownMenu_Initialize(frame, init, "MENU", 1, list)
    A.eq(frame.initialize, init)
    A.eq(frame.displayMode, "MENU")
    A.eq(frame.menuList, list)
  end)
end

local function test_initialize_stores_display_mode_only_for_menu()
  withFrameXML("retail", function()
    local frame = _G.CreateFrame("Frame", "PlainDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(frame, nil, "LIST")
    A.eq(frame.displayMode, nil)
    A.eq(frame.initialize, nil)
  end)
end

local function test_initialize_without_init_does_not_rerun_the_stored_one()
  withFrameXML("retail", function()
    local calls = 0
    local frame = _G.CreateFrame("Frame", "AgainDD", _G.UIParent, "UIDropDownMenuTemplate")
    local init = function()
      calls = calls + 1
    end
    _G.UIDropDownMenu_Initialize(frame, init, "MENU")
    _G.UIDropDownMenu_Initialize(frame, nil, "MENU")
    A.eq(calls, 1)
    A.eq(frame.initialize, init)
  end)
end

local function test_initialize_on_another_frame_closes_the_open_menu()
  withFrameXML("retail", function(w)
    openMenu({ { "One" } })
    newDropdown({ { "Other" } }, "OtherInitDD")
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

local function test_error_in_init_reaches_the_caller() -- (S4)
  withFrameXML("retail", function(w)
    local frame = _G.CreateFrame("Frame", "BoomDD", _G.UIParent, "UIDropDownMenuTemplate")
    A.errors(function()
      _G.UIDropDownMenu_Initialize(frame, function()
        error("init boom")
      end, "MENU")
    end, "init boom")
    -- Initialize stored init before calling it, so Toggle re-runs it and raises the same way.
    A.errors(function()
      _G.ToggleDropDownMenu(1, nil, frame)
    end, "init boom")
    A.eq(w.dropdown.building, nil)
    A.same(w.menus, {})
    A.same(w.errors, {})
    local ok = pcall(_G.UIDropDownMenu_Initialize, frame, function() end, "MENU") -- the world stays usable after the error
    A.eq(ok, true)
  end)
end

local function test_initialize_scratch_buttons_do_not_leak_into_the_next_menu()
  withFrameXML("retail", function(w)
    openMenu({ { "One" }, { "Two" } })
    A.same(texts(w), { "One", "Two" })
  end)
end

local function test_add_button_outside_initialize_or_toggle_opens_nothing()
  withFrameXML("retail", function(w)
    addItem({ "Stray" })
    A.same(w.menus, {})
    openMenu({ { "One" } })
    A.same(texts(w), { "One" })
  end)
end

local function test_add_button_copies_info_so_reuse_does_not_change_earlier_entries()
  withFrameXML("retail", function(w)
    local frame = _G.CreateFrame("Frame", "ReuseDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(frame, function(_, level)
      local info = {}
      info.text = "One"
      _G.UIDropDownMenu_AddButton(info, level)
      info.text = "Two"
      _G.UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    _G.ToggleDropDownMenu(1, nil, frame)
    A.same(texts(w), { "One", "Two" })
  end)
end

local function test_info_maps_to_entry_kinds()
  withFrameXML("retail", function(w)
    openMenu({
      { "T", { isTitle = true } },
      { "B", { notCheckable = true } },
      { "C", { isNotRadio = true, checked = true } },
      { "R" },
      { nil, { isTitle = true } },
    })
    local kinds, entries = {}, w.menus[1].entries
    for i, e in ipairs(entries) do
      kinds[i] = e.kind
    end
    A.same(kinds, { "title", "button", "checkbox", "radio", "divider" })
    A.eq(entries[3].checked, true)
    A.eq(entries[4].checked, false)
  end)
end

local function test_has_arrow_and_disabled_info_set_the_entry_flags()
  withFrameXML("retail", function(w)
    openMenu({ { "More", { hasArrow = true } }, { "Locked", { disabled = true } } })
    local entries = w.menus[1].entries
    A.eq(entries[1].hasSubmenu, true)
    A.eq(entries[2].enabled, false)
    A.eq(entries[1].enabled, true)
  end)
end

-- Mainline UIDropDownMenu.lua:460-463 and :472-476 (Classic :411-414, :423-427): notClickable sets info.disabled.
local function test_not_clickable_entry_is_disabled()
  withFrameXML("retail", function(w)
    openMenu({ { "Label", { notCheckable = true, notClickable = true, func = function() end } } })
    local entry = w.menus[1].entries[1]
    A.eq(entry.enabled, false)
    A.eq(Input.blockedReason(w, entry.frame, "click"), "disabled")
  end)
end

-- Mainline :466-476 (Classic :417-427): isTitle sets info.disabled; a divider is a title without text (S2).
local function test_title_and_divider_entries_are_disabled()
  withFrameXML("retail", function(w)
    openMenu({ { "Head", { isTitle = true } }, { nil, { isTitle = true } } })
    A.eq(w.menus[1].entries[1].enabled, false)
    A.eq(w.menus[1].entries[2].enabled, false)
  end)
end

local function test_function_checked_is_evaluated_with_the_entry_frame()
  withFrameXML("retail", function(w)
    local got
    openMenu({
      { "C", {
        isNotRadio = true,
        checked = function(self)
          got = self
          return true
        end,
      } },
    })
    A.eq(w.menus[1].entries[1].checked, true)
    A.eq(got, w.menus[1].entries[1].frame)
  end)
end

local function test_text_width_and_selected_value_round_trip()
  withFrameXML("retail", function()
    local frame = newDropdown({ { "One" } })
    _G.UIDropDownMenu_SetText(frame, "Hi")
    A.eq(_G.UIDropDownMenu_GetText(frame), "Hi")
    _G.UIDropDownMenu_SetWidth(frame, 100)
    A.eq(frame:GetWidth(), 150)
    _G.UIDropDownMenu_SetSelectedValue(frame, "v")
    A.eq(_G.UIDropDownMenu_GetSelectedValue(frame), "v")
  end)
end

local function test_install_skips_names_the_flavor_does_not_list()
  H.withWorld("retail", function(w)
    -- World:install reads self.globals.api (world.lua:215, World:install), so keep the real tables behind a metatable.
    w.globals = setmetatable({ framexml = { UIDropDownMenu_Initialize = true } }, { __index = w.globals })
    Dropdown.install(w)
    A.eq(type(rawget(_G, "UIDropDownMenu_Initialize")), "function")
    A.eq(rawget(_G, "ToggleDropDownMenu"), nil)
    A.eq(rawget(_G, "CloseDropDownMenus"), nil)
  end)
end

return function()
  test_initialize_calls_init_once_with_the_given_level_and_opens_nothing()
  test_initialize_stores_init_display_mode_and_menu_list()
  test_initialize_stores_display_mode_only_for_menu()
  test_initialize_without_init_does_not_rerun_the_stored_one()
  test_initialize_on_another_frame_closes_the_open_menu()
  test_error_in_init_reaches_the_caller()
  test_initialize_scratch_buttons_do_not_leak_into_the_next_menu()
  test_add_button_outside_initialize_or_toggle_opens_nothing()
  test_add_button_copies_info_so_reuse_does_not_change_earlier_entries()
  test_info_maps_to_entry_kinds()
  test_has_arrow_and_disabled_info_set_the_entry_flags()
  test_not_clickable_entry_is_disabled()
  test_title_and_divider_entries_are_disabled()
  test_function_checked_is_evaluated_with_the_entry_frame()
  test_text_width_and_selected_value_round_trip()
  test_install_skips_names_the_flavor_does_not_list()
end
