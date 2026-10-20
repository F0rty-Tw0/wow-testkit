-- Menu API fake picks: what a callback gets, and which levels MenuResponse and the pick leave open.
-- Split from test_menu.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")
local Input = require("input")

local withFrameXML = HF.withFrameXML
-- Task 4.1 row M8: a checkbox defaults to MenuResponse.Refresh (stays open), a radio to nil (closes)
-- (Blizzard_Menu/MenuTemplates.lua:341, Menu.lua:2233-2247).
local CHECKBOX_STAYS_OPEN, RADIO_STAYS_OPEN = true, false

local function noop() end

local open = HM.open
local field = HM.field
local click = HM.click

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

return function()
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
  test_callback_error_is_recorded_and_the_menu_still_closes()
  test_pick_on_a_title_or_a_disabled_entry_does_nothing()
  test_a_menu_the_callback_opened_is_not_closed_by_the_pick()
end
