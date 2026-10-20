-- UIDropDownMenu fake picks: the arguments func gets, the level a pick closes, and keepShownOnClick.
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

return function()
  test_pick_passes_entry_frame_args_checked_and_button_to_func()
  test_pick_on_classic_flavors_passes_four_args()
  test_pick_closes_its_level_before_calling_func()
  test_pick_in_a_submenu_leaves_the_parent_level_open()
  test_pick_without_func_still_closes()
  test_keep_shown_on_click_leaves_the_menu_open()
  test_keep_shown_on_click_flips_checked_before_func()
  test_func_error_is_recorded_and_the_menu_still_closes()
end
