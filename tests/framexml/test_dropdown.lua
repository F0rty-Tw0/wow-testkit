-- UIDropDownMenu fake: Initialize/AddButton/Toggle build menu levels that MenuFrames renders; picks run func.
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

local function test_function_checked_that_errors_reads_false_and_is_recorded()
  withFrameXML("retail", function(w)
    openMenu({
      { "C", {
        isNotRadio = true,
        checked = function()
          error("checked boom")
        end,
      } },
    })
    A.eq(w.menus[1].entries[1].checked, false)
    A.eq(#w.errors, 1)
    A.contains(tostring(w.errors[1].message), "checked boom")
  end)
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

local function test_toggle_beyond_level_three_errors()
  withFrameXML("retail", function()
    local frame = newDropdown({ { "One" } })
    A.errors(function()
      _G.ToggleDropDownMenu(4, nil, frame)
    end, "past DropDownList3")
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

-- Opens a one-entry checkbox menu on flavor whose func records its arguments; returns the entry frame and the record.
local function pickArgs(flavor)
  local got = {}
  withFrameXML(flavor, function(w)
    openMenu({
      {
        "C",
        {
          isNotRadio = true,
          checked = true,
          arg1 = "x",
          arg2 = "y",
          func = function(...)
            got.args = { n = select("#", ...), ... }
          end,
        },
      },
    })
    got.frame = w.menus[1].entries[1].frame
    Input.click(w, got.frame, "LeftButton")
  end)
  return got
end

local function test_pick_passes_entry_frame_args_checked_and_button_to_func()
  for _, flavor in ipairs({ "retail", "forever" }) do
    local got = pickArgs(flavor)
    A.eq(got.args.n, 5, flavor)
    A.eq(got.args[1], got.frame, flavor)
    A.eq(got.args[2], "x", flavor)
    A.eq(got.args[3], "y", flavor)
    A.eq(got.args[4], true, flavor)
    A.eq(got.args[5], "LeftButton", flavor)
  end
end

local function test_pick_on_classic_flavors_passes_four_args()
  for _, flavor in ipairs({ "mists", "vanilla", "tbc" }) do
    local got = pickArgs(flavor)
    A.eq(got.args.n, 4, flavor)
    A.eq(got.args[1], got.frame, flavor)
    A.eq(got.args[4], true, flavor)
  end
end

local function test_pick_closes_its_level_before_calling_func()
  withFrameXML("retail", function(w)
    local seen
    openMenu({
      { "Go", {
        notCheckable = true,
        func = function()
          seen = #w.menus
        end,
      } },
    })
    Input.click(w, w.menus[1].entries[1].frame, "LeftButton")
    A.eq(seen, 0)
    A.same(w.menus, {})
  end)
end

local function test_pick_in_a_submenu_leaves_the_parent_level_open()
  withFrameXML("retail", function(w)
    openMenu({ { "More", { hasArrow = true, menuList = { { "Nested", { notCheckable = true } } } } } })
    Input.enter(w, w.menus[1].entries[1].frame)
    Input.click(w, w.menus[2].entries[1].frame, "LeftButton")
    A.eq(#w.menus, 1)
    A.eq(_G.DropDownList1:IsShown(), true)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

local function test_keep_shown_on_click_flips_checked_before_func()
  withFrameXML("retail", function(w)
    local got
    openMenu({
      {
        "Toggle",
        {
          isNotRadio = true,
          checked = true,
          keepShownOnClick = true,
          func = function(_, _, _, checked)
            got = checked
          end,
        },
      },
    })
    Input.click(w, w.menus[1].entries[1].frame, "LeftButton")
    A.eq(got, false)
    A.eq(w.menus[1].entries[1].checked, false)
  end)
end

local function test_pick_without_func_still_closes()
  withFrameXML("retail", function(w)
    openMenu({ { "Go", { notCheckable = true } } })
    Input.click(w, w.menus[1].entries[1].frame, "LeftButton")
    A.same(w.menus, {})
  end)
end

local function test_keep_shown_on_click_leaves_the_menu_open()
  withFrameXML("retail", function(w)
    local calls = 0
    openMenu({
      {
        "Stay",
        {
          notCheckable = true,
          keepShownOnClick = true,
          func = function()
            calls = calls + 1
          end,
        },
      },
    })
    Input.click(w, w.menus[1].entries[1].frame, "LeftButton")
    A.eq(calls, 1)
    A.eq(#w.menus, 1)
  end)
end

local function test_func_error_is_recorded_and_the_menu_still_closes()
  withFrameXML("retail", function(w)
    openMenu({
      { "Boom", {
        notCheckable = true,
        func = function()
          error("boom")
        end,
      } },
    })
    Input.click(w, w.menus[1].entries[1].frame, "LeftButton")
    A.eq(#w.errors, 1)
    A.contains(tostring(w.errors[1].message), "boom")
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
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
    -- World:install reads self.globals.api (world.lua:242-243), so keep the real tables behind a metatable.
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
  test_function_checked_is_evaluated_with_the_entry_frame()
  test_function_checked_that_errors_reads_false_and_is_recorded()
  test_toggle_opens_level_one_owned_by_the_frame()
  test_toggle_again_on_the_owning_frame_closes_the_menu()
  test_toggle_on_another_frame_replaces_the_open_menu()
  test_toggle_without_a_frame_uses_the_owner_of_level_one()
  test_toggle_beyond_level_three_errors()
  test_toggle_on_a_frame_without_initialize_errors()
  test_pick_passes_entry_frame_args_checked_and_button_to_func()
  test_pick_on_classic_flavors_passes_four_args()
  test_pick_closes_its_level_before_calling_func()
  test_pick_in_a_submenu_leaves_the_parent_level_open()
  test_pick_without_func_still_closes()
  test_keep_shown_on_click_leaves_the_menu_open()
  test_keep_shown_on_click_flips_checked_before_func()
  test_func_error_is_recorded_and_the_menu_still_closes()
  test_entering_has_arrow_entry_calls_toggle_with_value_menu_list_and_entry()
  test_entering_has_arrow_entry_without_value_passes_its_text()
  test_entering_has_arrow_entry_opens_level_two_under_that_entry()
  test_entering_the_same_entry_again_keeps_its_submenu_open()
  test_close_drop_down_menus_closes_from_the_given_level()
  test_text_width_and_selected_value_round_trip()
  test_install_skips_names_the_flavor_does_not_list()
end
