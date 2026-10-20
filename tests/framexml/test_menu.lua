-- Menu API fake: MenuUtil.CreateContextMenu, descriptions rendered as levels, picks and MenuResponse.
local A = require("assert")
local Flavors = require("tools.flavors")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML
-- Task 4.1 row M8: a checkbox defaults to MenuResponse.Refresh (stays open), a radio to nil (closes)
-- (Blizzard_Menu/MenuTemplates.lua:341, Menu.lua:2233-2247).
local CHECKBOX_STAYS_OPEN, RADIO_STAYS_OPEN = true, false

local function noop() end

local function owner()
  return _G.CreateFrame("Frame", nil, _G.UIParent)
end

local function open(generator)
  return _G.MenuUtil.CreateContextMenu(owner(), generator)
end

local function field(level, name)
  local out = {}
  for i, entry in ipairs(level.entries) do
    out[i] = entry[name]
  end
  return out
end

local function click(w, depth, index)
  Input.click(w, w.menus[depth].entries[index].frame, "LeftButton")
end

local function test_installs_menu_globals_on_every_flavor()
  for _, flavor in ipairs(Flavors.list) do
    withFrameXML(flavor, function()
      A.eq(type(_G.MenuUtil.CreateContextMenu), "function")
      for _, key in ipairs({ "Open", "Refresh", "Close", "CloseAll" }) do
        A.eq(type(_G.MenuResponse[key]), "number", flavor .. " MenuResponse." .. key)
      end
      A.eq(type(_G.MenuInputContext.MouseButton), "number")
    end)
  end
end

local function test_generator_gets_owner_and_root_and_fills_level_one()
  withFrameXML("retail", function(w)
    local o, seen = owner(), nil
    _G.MenuUtil.CreateContextMenu(o, function(ownerArg, root)
      seen = ownerArg
      root:CreateButton("One", noop)
      root:CreateTitle("Two")
    end)
    A.eq(seen, o)
    A.eq(w.menus[1].owner, o)
    A.eq(w.menus[1].parentIndex, nil)
    A.same(field(w.menus[1], "text"), { "One", "Two" })
  end)
end

local function test_builders_map_to_entry_kinds()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("B", noop)
      root:CreateCheckbox("C", noop, noop)
      root:CreateRadio("R", noop, noop)
      root:CreateTitle("T")
      root:CreateDivider()
    end)
    A.same(field(w.menus[1], "kind"), { "button", "checkbox", "radio", "title", "divider" })
  end)
end

local function test_checkbox_checked_comes_from_is_selected_called_with_data()
  withFrameXML("retail", function(w)
    local data, got = {}, nil
    open(function(_, root)
      root:CreateCheckbox("C", function(d)
        got = d
        return true
      end, noop, data)
    end)
    A.eq(got, data)
    A.eq(w.menus[1].entries[1].checked, true)
  end)
end

local function test_enabled_accepts_a_boolean_or_a_predicate_of_the_description()
  withFrameXML("retail", function(w)
    local seen, predicate
    open(function(_, root)
      root:CreateButton("A", noop):SetEnabled(false)
      predicate = root:CreateButton("B", noop)
      predicate:SetEnabled(function(description)
        seen = description
        return false
      end)
      root:CreateButton("C", noop)
    end)
    A.same(field(w.menus[1], "enabled"), { false, false, true })
    A.eq(seen, predicate)
  end)
end

local function test_button_callback_gets_data_input_data_and_menu()
  withFrameXML("retail", function(w)
    local data, args = {}, nil
    local menu = open(function(_, root)
      root:CreateButton("Go", function(...)
        args = { ... }
      end, data)
    end)
    click(w, 1, 1)
    A.eq(args[1], data)
    A.eq(args[2].context, _G.MenuInputContext.MouseButton)
    A.eq(args[2].buttonName, "LeftButton")
    A.eq(args[3], menu)
  end)
end

local function test_pick_passes_the_button_name()
  withFrameXML("retail", function(w)
    local input
    open(function(_, root)
      root:CreateButton("Go", function(_, menuInputData)
        input = menuInputData
      end)
    end)
    w.menus[1].pick(1, "RightButton")
    A.eq(input.buttonName, "RightButton")
  end)
end

local function test_checkbox_set_selected_gets_data_input_data_and_menu()
  withFrameXML("retail", function(w)
    local data, args = {}, nil
    local menu = open(function(_, root)
      root:CreateCheckbox("C", function()
        return false
      end, function(...)
        args = { ... }
      end, data)
    end)
    click(w, 1, 1)
    A.eq(args[1], data)
    A.eq(args[2].buttonName, "LeftButton")
    A.eq(args[3], menu)
  end)
end

local function test_button_pick_closes_the_menu_by_default()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("Go", noop)
    end)
    click(w, 1, 1)
    A.eq(#w.menus, 0)
  end)
end

local function pickLeavesOpen(builder)
  local stays
  withFrameXML("retail", function(w)
    open(function(_, root)
      root[builder](root, "X", noop, noop)
    end)
    click(w, 1, 1)
    stays = w.menus[1] ~= nil
  end)
  return stays
end

local function test_checkbox_pick_default_response()
  A.eq(pickLeavesOpen("CreateCheckbox"), CHECKBOX_STAYS_OPEN)
end

local function test_radio_pick_default_response()
  A.eq(pickLeavesOpen("CreateRadio"), RADIO_STAYS_OPEN)
end

local function test_button_without_callback_pick_leaves_the_menu_open()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("Inert")
    end)
    click(w, 1, 1)
    A.eq(#w.menus, 1)
  end)
end

local function test_open_response_keeps_the_menu_without_rereading_is_selected()
  withFrameXML("retail", function(w)
    local on = false
    open(function(_, root)
      root:CreateCheckbox("C", function()
        return on
      end, function()
        on = not on
        return _G.MenuResponse.Open
      end)
    end)
    click(w, 1, 1)
    A.eq(#w.menus, 1)
    A.eq(w.menus[1].entries[1].checked, false)
  end)
end

local function test_refresh_response_rereads_is_selected_without_running_the_generator()
  withFrameXML("retail", function(w)
    local runs, on = 0, false
    open(function(_, root)
      runs = runs + 1
      root:CreateCheckbox("C", function()
        return on
      end, function()
        on = not on
      end)
    end)
    local frame = w.menus[1].entries[1].frame
    click(w, 1, 1)
    A.eq(runs, 1)
    A.eq(w.menus[1].entries[1].checked, true)
    A.eq(w.menus[1].entries[1].frame, frame)
  end)
end

local function test_close_response_closes_only_the_picked_level_and_deeper()
  withFrameXML("retail", function(w)
    open(function(_, root)
      local more = root:CreateButton("More")
      more:CreateButton("Deep", function()
        return _G.MenuResponse.Close
      end)
    end)
    Input.enter(w, w.menus[1].entries[1].frame)
    click(w, 2, 1)
    A.eq(#w.menus, 1)
  end)
end

local function test_submenu_pick_gets_the_submenu_menu_object()
  withFrameXML("retail", function(w)
    local got
    local menu = open(function(_, root)
      root:CreateButton("More"):CreateButton("Deep", function(_, _, m)
        got = m
        return _G.MenuResponse.Open
      end)
    end)
    Input.enter(w, w.menus[1].entries[1].frame)
    click(w, 2, 1)
    A.eq(got, w.menus[2].frame)
    A.eq(menu, w.menus[1].frame)
    got:Close()
    A.eq(#w.menus, 1)
  end)
end

local function test_picking_a_submenu_root_with_a_callback_keeps_the_menu_open()
  withFrameXML("retail", function(w)
    local called = 0
    open(function(_, root)
      local more = root:CreateButton("More", function()
        called = called + 1
      end)
      more:CreateButton("Deep", noop)
    end)
    click(w, 1, 1)
    A.eq(called, 1)
    A.eq(#w.menus >= 1, true)
  end)
end

local function test_empty_generator_opens_nothing_and_returns_nil()
  withFrameXML("retail", function(w)
    local menu = open(noop)
    A.eq(menu, nil)
    A.eq(#w.menus, 0)
  end)
end

local function test_empty_generator_still_closes_the_open_menu()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("Old", noop)
    end)
    open(noop)
    A.eq(#w.menus, 0)
  end)
end

local function test_extra_arguments_reach_the_generator()
  withFrameXML("retail", function()
    local got
    _G.MenuUtil.CreateContextMenu(owner(), function(_, root, a, b)
      got = { a, b }
      root:CreateButton("X", noop)
    end, "a", "b")
    A.same(got, { "a", "b" })
  end)
end

local function test_callback_error_is_recorded_and_the_menu_still_closes()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("Boom", function()
        error("boom")
      end)
    end)
    click(w, 1, 1)
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "boom")
    A.eq(#w.menus, 0)
    A.eq(next(w.menus), nil)
  end)
end

local function test_generator_error_is_recorded_and_the_menu_opens_with_what_was_built()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("Kept", noop)
      error("gen boom")
    end)
    A.eq(#w.errors, 1)
    A.same(field(w.menus[1], "text"), { "Kept" })
  end)
end

local function twoLevelMenu(picked)
  return function(_, root)
    root:CreateButton("Leaf", noop)
    local more = root:CreateButton("More")
    more:CreateButton("Deep", function()
      picked.deep = true
    end)
  end
end

local function test_submenu_opens_on_enter_and_lists_its_children()
  withFrameXML("retail", function(w)
    open(twoLevelMenu({}))
    A.eq(w.menus[1].entries[2].hasSubmenu, true)
    Input.enter(w, w.menus[1].entries[2].frame)
    A.same(field(w.menus[2], "text"), { "Deep" })
    A.eq(w.menus[2].parentIndex, 2)
  end)
end

local function test_submenu_leaf_pick_runs_the_callback_and_closes_every_level()
  withFrameXML("retail", function(w)
    local picked = {}
    open(twoLevelMenu(picked))
    Input.enter(w, w.menus[1].entries[2].frame)
    click(w, 2, 1)
    A.eq(picked.deep, true)
    A.eq(#w.menus, 0)
  end)
end

local function test_opening_another_menu_replaces_the_open_one()
  withFrameXML("retail", function(w)
    open(twoLevelMenu({}))
    Input.enter(w, w.menus[1].entries[2].frame)
    open(function(_, root)
      root:CreateButton("Other", noop)
    end)
    A.eq(#w.menus, 1)
    A.same(field(w.menus[1], "text"), { "Other" })
  end)
end

local function test_menu_close_closes_every_level_assumed()
  withFrameXML("retail", function(w)
    local menu = open(twoLevelMenu({}))
    Input.enter(w, w.menus[1].entries[2].frame)
    menu:Close()
    A.eq(#w.menus, 0)
  end)
end

local function test_closing_a_replaced_menu_does_not_close_the_new_one_assumed()
  withFrameXML("retail", function(w)
    local old = open(twoLevelMenu({}))
    open(twoLevelMenu({}))
    old:Close()
    A.eq(#w.menus, 1)
  end)
end

local function test_pick_on_a_title_or_a_disabled_entry_does_nothing()
  withFrameXML("retail", function(w)
    local called = 0
    open(function(_, root)
      root:CreateTitle("T")
      root
        :CreateButton("Off", function()
          called = called + 1
        end)
        :SetEnabled(false)
    end)
    w.menus[1].pick(1, "LeftButton")
    w.menus[1].pick(2, "LeftButton")
    A.eq(called, 0)
    A.eq(#w.menus, 1)
  end)
end

local function test_a_menu_the_callback_opened_is_not_closed_by_the_pick()
  withFrameXML("retail", function(w)
    open(function(_, root)
      root:CreateButton("Open another", function()
        open(function(_, other)
          other:CreateButton("Second", noop)
        end)
      end)
    end)
    click(w, 1, 1)
    A.same(field(w.menus[1], "text"), { "Second" })
  end)
end

local function test_rebuild_reruns_the_generator_and_keeps_the_frames()
  withFrameXML("retail", function(w)
    local label = "Old"
    local menu = open(function(_, root)
      root:CreateButton("More"):CreateButton(label, noop)
      root:CreateButton("Second", noop)
    end)
    Input.enter(w, w.menus[1].entries[1].frame)
    local frame1, frame2 = w.menus[1].entries[1].frame, w.menus[2].frame
    label = "New"
    w.menus[1].rebuild()
    A.same(field(w.menus[2], "text"), { "New" })
    A.eq(w.menus[1].entries[1].frame, frame1)
    A.eq(w.menus[2].frame, frame2)
    A.eq(menu, w.menus[1].frame)
    menu:Close()
    A.eq(#w.menus, 0)
  end)
end

return function()
  test_installs_menu_globals_on_every_flavor()
  test_generator_gets_owner_and_root_and_fills_level_one()
  test_builders_map_to_entry_kinds()
  test_checkbox_checked_comes_from_is_selected_called_with_data()
  test_enabled_accepts_a_boolean_or_a_predicate_of_the_description()
  test_button_callback_gets_data_input_data_and_menu()
  test_pick_passes_the_button_name()
  test_checkbox_set_selected_gets_data_input_data_and_menu()
  test_button_pick_closes_the_menu_by_default()
  test_checkbox_pick_default_response()
  test_radio_pick_default_response()
  test_button_without_callback_pick_leaves_the_menu_open()
  test_open_response_keeps_the_menu_without_rereading_is_selected()
  test_refresh_response_rereads_is_selected_without_running_the_generator()
  test_close_response_closes_only_the_picked_level_and_deeper()
  test_submenu_pick_gets_the_submenu_menu_object()
  test_picking_a_submenu_root_with_a_callback_keeps_the_menu_open()
  test_empty_generator_opens_nothing_and_returns_nil()
  test_empty_generator_still_closes_the_open_menu()
  test_extra_arguments_reach_the_generator()
  test_callback_error_is_recorded_and_the_menu_still_closes()
  test_generator_error_is_recorded_and_the_menu_opens_with_what_was_built()
  test_submenu_opens_on_enter_and_lists_its_children()
  test_submenu_leaf_pick_runs_the_callback_and_closes_every_level()
  test_opening_another_menu_replaces_the_open_one()
  test_menu_close_closes_every_level_assumed()
  test_closing_a_replaced_menu_does_not_close_the_new_one_assumed()
  test_pick_on_a_title_or_a_disabled_entry_does_nothing()
  test_a_menu_the_callback_opened_is_not_closed_by_the_pick()
  test_rebuild_reruns_the_generator_and_keeps_the_frames()
end
