-- Menu frames: levels rendered into real DropDownList / unnamed frames, entry scripts, close and focus rules.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")
local MenuFrames = require("framexml.fakes.menu_frames")

local withFrameXML = HF.withFrameXML

local function entry(kind, text, extra)
  local e = { kind = kind, text = text, enabled = true, checked = false, hasSubmenu = false }
  for k, v in pairs(extra or {}) do
    e[k] = v
  end
  return e
end

-- A level recording its picks and submenu opens in log; namePrefix nil makes an unnamed (Menu API style) level.
local function newLevel(entries, namePrefix, log)
  log = log or {}
  return {
    entries = entries,
    namePrefix = namePrefix,
    pick = function(index, button)
      log[#log + 1] = { "pick", index, button }
    end,
    openSubmenu = function(index)
      log[#log + 1] = { "open", index }
    end,
    rebuild = function() end,
  },
    log
end

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

local function test_open_rejects_a_depth_that_leaves_a_gap()
  withFrameXML("retail", function(w)
    A.errors(function()
      MenuFrames.open(w, 2, newLevel({ entry("button", "A") }, "DropDownList2"))
    end, "leaves a gap")
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

local function test_menu_api_titles_and_dividers_have_mouse_disabled()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("title", "Head"), entry("divider") }, nil)
    MenuFrames.open(w, 1, level)
    for _, e in ipairs(level.entries) do
      A.contains(Input.blockedReason(w, e.frame, "click"), "mouse disabled")
      A.contains(Input.blockedReason(w, e.frame, "enter"), "mouse disabled")
    end
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

local function test_close_hides_the_level_and_deeper_ones_and_clears_menus()
  withFrameXML("retail", function(w)
    local first = newLevel({ entry("button", "A") }, "DropDownList1")
    local second = newLevel({ entry("button", "B") }, "DropDownList2")
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 2, second)
    MenuFrames.close(w, 2)
    A.eq(#w.menus, 1)
    A.eq(_G.DropDownList1:IsShown(), true)
    A.eq(_G.DropDownList2:IsShown(), false)
    MenuFrames.close(w, 1)
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

-- S3 (assumed): OnLeave on hide is from Blizzard's comments; the `false` motion argument is inferred.
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

local function test_close_fires_on_leave_without_motion_on_the_focused_entry_assumed()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("button", "A") }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    local frame, leaves = level.entries[1].frame, {}
    frame:SetScript("OnLeave", function(_, motion)
      leaves[#leaves + 1] = motion
    end)
    Input.enter(w, frame)
    MenuFrames.close(w, 1)
    A.same(leaves, { false })
    A.eq(w.input.mouseFocus, nil)
  end)
end

local function test_close_survives_an_on_leave_that_closes_the_menus()
  withFrameXML("retail", function(w)
    local first = newLevel({ entry("button", "A") }, "DropDownList1")
    local second = newLevel({ entry("button", "B") }, "DropDownList2")
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 2, second)
    local frame = second.entries[1].frame
    frame:SetScript("OnLeave", function()
      MenuFrames.close(w, 1)
    end)
    Input.enter(w, frame)
    MenuFrames.close(w, 1)
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

local function test_close_leaves_focus_outside_the_level_alone()
  withFrameXML("retail", function(w)
    local level = newLevel({ entry("button", "A") }, "DropDownList1")
    MenuFrames.open(w, 1, level)
    local outside = _G.CreateFrame("Button", nil, _G.UIParent)
    Input.enter(w, outside)
    MenuFrames.close(w, 1)
    A.eq(w.input.mouseFocus, outside)
  end)
end

local function test_entering_another_entry_leaves_the_old_one_once()
  withFrameXML("retail", function(w)
    local first = newLevel({ entry("button", "A") }, "DropDownList1")
    local second = newLevel({ entry("button", "C") }, "DropDownList2")
    second.parentIndex = 1
    MenuFrames.open(w, 1, first)
    MenuFrames.open(w, 2, second)
    local leaves = 0
    second.entries[1].frame:SetScript("OnLeave", function()
      leaves = leaves + 1
    end)
    Input.enter(w, second.entries[1].frame)
    Input.enter(w, first.entries[1].frame)
    A.eq(leaves, 1)
  end)
end

local function test_reopening_reuses_frames_and_hides_unused_ones()
  withFrameXML("retail", function(w)
    MenuFrames.open(w, 1, newLevel({ entry("button", "A"), entry("button", "B"), entry("button", "C") }, "DropDownList1"))
    local one, two = _G.DropDownList1Button1, _G.DropDownList1Button2
    MenuFrames.close(w, 1)
    MenuFrames.open(w, 1, newLevel({ entry("button", "Z") }, "DropDownList1"))
    A.eq(_G.DropDownList1Button1, one)
    A.eq(one.NormalText:GetText(), "Z")
    A.eq(one:IsShown(), true)
    A.eq(_G.DropDownList1Button2, two)
    A.eq(two:IsShown(), false)
  end)
end

return function()
  test_install_sets_empty_menus_and_notes()
  test_install_creates_hidden_drop_down_lists_before_the_lazy_frames()
  test_drop_down_lists_are_buttons_assumed()
  test_open_renders_entries_as_named_buttons_with_label_text()
  test_open_unnamed_level_parents_its_frames_to_ui_parent()
  test_open_closes_the_levels_from_its_depth()
  test_open_rejects_a_depth_that_leaves_a_gap()
  test_entry_click_runs_pick_with_index_and_button()
  test_entry_enter_with_a_submenu_calls_open_submenu()
  test_entry_enter_without_a_submenu_closes_deeper_levels()
  test_entering_a_disabled_entry_with_a_submenu_only_closes_deeper_levels()
  test_a_replaced_entry_script_removes_the_kit_behavior()
  test_menu_api_titles_and_dividers_have_mouse_disabled()
  test_drop_down_titles_and_dividers_close_deeper_levels_on_enter()
  test_disabled_entries_are_disabled_buttons()
  test_close_hides_the_level_and_deeper_ones_and_clears_menus()
  test_close_fires_on_leave_without_motion_on_the_focused_entry_assumed()
  test_close_survives_an_on_leave_that_closes_the_menus()
  test_close_leaves_focus_outside_the_level_alone()
  test_entering_another_entry_leaves_the_old_one_once()
  test_reopening_reuses_frames_and_hides_unused_ones()
end
