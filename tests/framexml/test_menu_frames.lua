-- Menu frames: levels rendered into real DropDownList / unnamed frames, and their entry scripts.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")
local Input = require("input")
local MenuFrames = require("framexml.fakes.menu_frames")

local withFrameXML = HF.withFrameXML

local entry = HM.entry
local newLevel = HM.newLevel

local function test_install_sets_empty_menus_and_notes()
  withFrameXML("retail", function(w)
    A.same(w.menus, {})
    A.same(w.notes, {})
  end)
end

local function test_install_creates_hidden_drop_down_lists_before_the_lazy_frames()
  withFrameXML("retail", function(w)
    for i = 1, 3 do
      local list = _G["DropDownList" .. i]
      A.eq(list:IsShown(), false)
      A.eq(w.unscripted["frame:DropDownList" .. i], nil)
    end
  end)
end

-- S9 (assumed): the XML that defines the shipped lists is not in the mirror; the Lua-made lists are Buttons.
local function test_drop_down_lists_are_buttons_assumed()
  withFrameXML("retail", function()
    for i = 1, 3 do
      A.eq(_G["DropDownList" .. i]:GetObjectType(), "Button")
    end
  end)
end

local function test_open_renders_entries_as_named_buttons_with_label_text()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("button", "|cff00ff00Open|r"), entry("button", "Close") }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    local button = _G.DropDownList1Button1
    A.eq(level.entries[1].frame, button)
    A.eq(button:GetObjectType(), "Button")
    A.eq(button.NormalText:GetText(), "|cff00ff00Open|r")
    A.eq(level.entries[2].frame, _G.DropDownList1Button2)
    A.eq(w.menus[1], level)
    A.eq(_G.DropDownList1:IsShown(), true)
    A.eq(level.frame, _G.DropDownList1)
  end)
end

local function test_open_unnamed_level_parents_its_frames_to_ui_parent()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("button", "A") }, nil)
    MenuFrames.open(w, 1, level)
    A.eq(level.frame:GetName(), nil)
    A.eq(level.frame:GetParent(), _G.UIParent)
    A.eq(level.entries[1].frame:GetName(), nil)
    A.eq(level.entries[1].frame:GetParent(), level.frame)
  end)
end

local function test_open_closes_the_levels_from_its_depth()
  withFrameXML("retail", function(w)
    local first = newLevel({ entry("button", "A") }, "DropDownList1")
    local second = newLevel({ entry("button", "B") }, "DropDownList1")
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 1, second)
    A.eq(#w.menus, 1)
    A.eq(w.menus[1], second)
    A.eq(second.entries[1].frame.NormalText:GetText(), "B")
  end)
end

-- ToggleDropDownMenu can show DropDownList2 with list 1 hidden (Mainline UIDropDownMenu.lua:1049-1202).
local function test_open_above_a_closed_level_tracks_and_closes_it()
  withFrameXML("retail", function(w)
    local second = newLevel({ entry("button", "A") }, "DropDownList2")
    MenuFrames.open(w, 2, second)
    MenuFrames.open(w, 3, newLevel({ entry("button", "B") }, "DropDownList3"))
    A.eq(w.menus[1], nil)
    A.eq(_G.DropDownList2:IsShown(), true)
    Input.enter(w, second.entries[1].frame)
    A.eq(w.menus[3], nil)
    A.eq(_G.DropDownList3:IsShown(), false)
    MenuFrames.close(w, 1)
    A.eq(next(w.menus), nil)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

local function test_entry_click_runs_pick_with_index_and_button()
  withFrameXML("retail", function(w)
    local level, log = newLevel({ entry("button", "A"), entry("button", "B") }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    Input.click(w, level.entries[2].frame, "LeftButton")
    A.eq(#log, 1)
    A.same(log[1], { "pick", 2, "LeftButton" })
  end)
end

local function test_entry_enter_with_a_submenu_calls_open_submenu()
  withFrameXML("retail", function(w)
    local level, log = newLevel({ entry("button", "More", { hasSubmenu = true }) }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    Input.enter(w, level.entries[1].frame)
    A.same(log, { { "open", 1 } })
  end)
end

local function test_entry_enter_without_a_submenu_closes_deeper_levels()
  withFrameXML("retail", function(w)
    local first = newLevel({ entry("button", "A") }, "DropDownList1")
    local second = newLevel({ entry("button", "B") }, "DropDownList2")
    second.parentIndex = 1
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 2, second)
    Input.enter(w, first.entries[1].frame)
    A.eq(#w.menus, 1)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

local function test_a_replaced_entry_script_removes_the_kit_behavior()
  withFrameXML("retail", function(w)
    local level, log = newLevel({ entry("button", "A") }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    level.entries[1].frame:SetScript("OnClick", function() end)
    Input.click(w, level.entries[1].frame, "LeftButton")
    A.eq(#log, 0)
  end)
end

-- M18: a Menu API title or divider is a Frame element with the element OnEnter (Menu.lua:1129), which enables its mouse
-- (I5), and no OnClick.
local function test_menu_api_titles_and_dividers_take_the_enter_but_no_click()
  withFrameXML("retail", function(w)
    local level, log = newLevel({ entry("title", "Head"), entry("divider") }, nil)
    MenuFrames.open(w, 1, level)
    for _, e in ipairs(level.entries) do
      A.eq(Input.blockedReason(w, e.frame, "enter"), nil)
      A.eq(e.frame:GetScript("OnClick"), nil)
      Input.click(w, e.frame, "LeftButton")
    end
    A.eq(#log, 0)
  end)
end

-- A UIDropDownMenu title or divider is a disabled Button under an InvisibleButton whose OnEnter closes the deeper
-- levels (Mainline UIDropDownMenu.lua:153-154, :466-475; Classic :180-182, :417-427), as for any disabled entry (S11).
local function test_drop_down_titles_and_dividers_close_deeper_levels_on_enter()
  withFrameXML("retail", function(w)
    local disabled = { enabled = false }
    local first, log = newLevel({ entry("title", "Head", disabled), entry("divider", nil, disabled) }, "DropDownList1")
    MenuFrames.open(w, 1, first)
    for _, e in ipairs(first.entries) do
      MenuFrames.open(w, 2, newLevel({ entry("button", "B") }, "DropDownList2"))
      Input.enter(w, e.frame)
      A.eq(#w.menus, 1)
      A.eq(Input.blockedReason(w, e.frame, "click"), "disabled")
    end
    A.same(log, {})
  end)
end

local function test_disabled_entries_are_disabled_buttons()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("button", "Locked", { enabled = false }) }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    local frame = level.entries[1].frame
    A.eq(frame:IsEnabled(), false)
    A.eq(Input.blockedReason(w, frame, "click"):find("mouse", 1, true), nil)
  end)
end

-- Mainline UIDropDownMenu.lua:153-154, :471-475: a disabled entry's InvisibleButton only closes deeper levels.
local function test_entering_a_disabled_entry_with_a_submenu_only_closes_deeper_levels()
  withFrameXML("retail", function(w)
    local first, log = newLevel({ entry("button", "A", { enabled = false, hasSubmenu = true }) }, "DropDownList1")
    local second = newLevel({ entry("button", "B") }, "DropDownList2")
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 2, second)
    Input.enter(w, first.entries[1].frame)
    A.same(log, {})
    A.eq(#w.menus, 1)
  end)
end

return function()
  test_install_sets_empty_menus_and_notes()
  test_install_creates_hidden_drop_down_lists_before_the_lazy_frames()
  test_drop_down_lists_are_buttons_assumed()
  test_open_renders_entries_as_named_buttons_with_label_text()
  test_open_unnamed_level_parents_its_frames_to_ui_parent()
  test_open_closes_the_levels_from_its_depth()
  test_open_above_a_closed_level_tracks_and_closes_it()
  test_entry_click_runs_pick_with_index_and_button()
  test_entry_enter_with_a_submenu_calls_open_submenu()
  test_entry_enter_without_a_submenu_closes_deeper_levels()
  test_entering_a_disabled_entry_with_a_submenu_only_closes_deeper_levels()
  test_a_replaced_entry_script_removes_the_kit_behavior()
  test_menu_api_titles_and_dividers_take_the_enter_but_no_click()
  test_drop_down_titles_and_dividers_close_deeper_levels_on_enter()
  test_disabled_entries_are_disabled_buttons()
end
