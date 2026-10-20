-- Widget input methods: mouse state, mouse-over queries, Button and CheckButton clicks, EditBox focus and text.
local A = require("assert")
local BehaviourInput = require("ui.behaviour_input")
local HW = require("tests.helpers.widgets")
local Rec = require("tests.helpers.input")

local withWidgets = HW.withWidgets

local function test_widgets_install_creates_the_input_state()
  withWidgets("retail", function(w)
    A.eq(type(w.input), "table")
    A.eq(w.input.mouseFocus, nil)
    A.eq(w.input.editFocus, nil)
  end)
end

local function test_button_check_button_and_edit_box_start_mouse_enabled_assumed() -- (I5)
  withWidgets("retail", function()
    for _, kind in ipairs({ "Button", "CheckButton", "EditBox" }) do
      local f = _G.CreateFrame(kind)
      A.eq(f:IsMouseClickEnabled(), true, kind)
      A.eq(f:IsMouseMotionEnabled(), true, kind)
    end
    A.eq(_G.CreateFrame("Frame"):IsMouseEnabled(), false)
  end)
end

-- (I5, follows wiki API_ScriptRegion_EnableMouse) any of the four mouse scripts implies
-- EnableMouse(true); OnClick and clearing a script enable nothing.
local function test_mouse_scripts_enable_click_and_motion() -- (I5)
  withWidgets("retail", function()
    for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp" }) do
      local f = _G.CreateFrame("Frame")
      f:SetScript(script, function() end)
      A.eq(f:IsMouseMotionEnabled(), true, script)
      A.eq(f:IsMouseClickEnabled(), true, script)
    end
    local g = _G.CreateFrame("Frame")
    g:SetScript("OnLeave", nil)
    A.eq(g:IsMouseEnabled(), false)
  end)
end

local function test_enable_mouse_sets_click_and_motion_together()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:EnableMouse(true)
    A.eq(f:IsMouseClickEnabled(), true)
    A.eq(f:IsMouseMotionEnabled(), true)
    f:EnableMouse(false)
    A.eq(f:IsMouseClickEnabled(), false)
    A.eq(f:IsMouseMotionEnabled(), false)
    local b = _G.CreateFrame("Button")
    b:EnableMouse(false)
    A.eq(b:IsMouseEnabled(), false)
  end)
end

local function test_click_and_motion_are_set_separately()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:SetMouseClickEnabled(true)
    A.eq(f:IsMouseClickEnabled(), true)
    A.eq(f:IsMouseMotionEnabled(), false)
    A.eq(f:IsMouseEnabled(), true)
    f:SetMouseClickEnabled(false)
    f:SetMouseMotionEnabled(true)
    A.eq(f:IsMouseEnabled(), true)
  end)
end

local function test_enable_mouse_motion_sets_motion_only()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:EnableMouseMotion(true)
    A.eq(f:IsMouseMotionEnabled(), true)
    A.eq(f:IsMouseClickEnabled(), false)
    f:EnableMouseMotion(false)
    A.eq(f:IsMouseMotionEnabled(), false)
  end)
end

local function test_is_mouse_over_covers_descendants_and_motion_focus_is_exact()
  withWidgets("retail", function(w)
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Button", nil, parent)
    w.input.mouseFocus = child
    A.eq(child:IsMouseOver(), true)
    A.eq(parent:IsMouseOver(), true)
    A.eq(_G.CreateFrame("Frame"):IsMouseOver(), false)
    A.eq(child:IsMouseMotionFocus(), true)
    A.eq(parent:IsMouseMotionFocus(), false)
  end)
end

local function test_mouse_queries_are_not_counted_as_unscripted()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    f:EnableMouse(true)
    f:EnableMouseMotion(true)
    f:SetMouseClickEnabled(true)
    f:SetMouseMotionEnabled(true)
    f:SetScript("OnEnter", function() end)
    f:IsMouseEnabled()
    f:IsMouseClickEnabled()
    f:IsMouseMotionEnabled()
    f:IsMouseOver()
    f:IsMouseMotionFocus()
    A.eq(next(w.unscripted), nil)
  end)
end

local function test_disable_and_enable_fire_their_scripts_only_on_change_assumed() -- (I1)
  withWidgets("retail", function()
    local b = _G.CreateFrame("Button")
    local log = Rec.record(b, { "OnEnable", "OnDisable" })
    A.eq(b:IsEnabled(), true)
    b:Enable()
    b:Disable()
    b:Disable()
    b:SetEnabled(true)
    A.same(log, { { "OnDisable" }, { "OnEnable" } })
    A.eq(b:IsEnabled(), true)
  end)
end

local function test_click_runs_the_three_scripts_with_button_and_down_false() -- (I3)
  withWidgets("retail", function()
    local b = _G.CreateFrame("Button")
    local log = Rec.record(b, { "PreClick", "OnClick", "PostClick" })
    b:Click()
    b:Click("RightButton")
    A.same(log, {
      { "PreClick", "LeftButton", false },
      { "OnClick", "LeftButton", false },
      { "PostClick", "LeftButton", false },
      { "PreClick", "RightButton", false },
      { "OnClick", "RightButton", false },
      { "PostClick", "RightButton", false },
    })
  end)
end

local function test_click_passes_is_down_to_the_scripts() -- (I3)
  withWidgets("retail", function()
    local b = _G.CreateFrame("Button")
    local log = Rec.record(b, { "PreClick", "OnClick", "PostClick" })
    b:Click("RightButton", true)
    b:Click("LeftButton", 1)
    A.same(log, {
      { "PreClick", "RightButton", true },
      { "OnClick", "RightButton", true },
      { "PostClick", "RightButton", true },
      { "PreClick", "LeftButton", true },
      { "OnClick", "LeftButton", true },
      { "PostClick", "LeftButton", true },
    })
  end)
end

local function test_click_during_its_own_click_does_nothing() -- (I3)
  for _, script in ipairs({ "PreClick", "OnClick", "PostClick" }) do
    withWidgets("retail", function()
      local b = _G.CreateFrame("Button")
      local clicks = 0
      b:SetScript(script, function(self)
        clicks = clicks + 1
        self:Click()
      end)
      b:Click()
      A.eq(clicks, 1, script)
      b:Click()
      A.eq(clicks, 2, script)
    end)
  end
end

local function test_click_after_an_erroring_on_click_still_runs() -- (I3)
  withWidgets("retail", function(w)
    local b = _G.CreateFrame("Button")
    local clicks = 0
    b:SetScript("OnClick", function()
      clicks = clicks + 1
      if clicks == 1 then
        error("boom")
      end
    end)
    b:Click()
    b:Click()
    A.eq(clicks, 2)
    A.eq(#w.errors, 1)
    A.contains(tostring(w.errors[1].message), "boom")
  end)
end

local function test_nested_mouse_click_keeps_the_outer_click_in_progress() -- (I3)
  withWidgets("retail", function(w)
    local b = _G.CreateFrame("Button")
    local clicks = 0
    b:SetScript("OnClick", function(self)
      clicks = clicks + 1
      if clicks == 1 then
        BehaviourInput.runClick(w, self, "LeftButton", false)
      end
    end)
    b:SetScript("PostClick", function(self)
      self:Click()
    end)
    b:Click()
    A.eq(clicks, 2)
  end)
end

local function test_check_button_click_flips_the_state_before_the_scripts_assumed() -- (I4)
  withWidgets("retail", function()
    local c = _G.CreateFrame("CheckButton")
    local seen = {}
    for _, script in ipairs({ "PreClick", "OnClick" }) do
      c:SetScript(script, function(self)
        seen[#seen + 1] = script .. "=" .. tostring(self:GetChecked())
      end)
    end
    c:Click()
    A.same(seen, { "PreClick=true", "OnClick=true" })
    c:Click()
    A.eq(c:GetChecked(), false)
  end)
end

local function test_register_for_clicks_defaults_to_left_button_up() -- (I2)
  withWidgets("retail", function(w)
    local b = _G.CreateFrame("Button")
    A.eq(BehaviourInput.isRegistered(w, b, "LeftButton", "Up"), true)
    A.eq(BehaviourInput.isRegistered(w, b, "LeftButton", "Down"), false)
    A.eq(BehaviourInput.isRegistered(w, b, "RightButton", "Up"), false)
  end)
end

local function test_register_for_clicks_accepts_any_and_named_types() -- (I2)
  withWidgets("retail", function(w)
    local b = _G.CreateFrame("Button")
    b:RegisterForClicks("AnyUp")
    A.eq(BehaviourInput.isRegistered(w, b, "RightButton", "Up"), true)
    A.eq(BehaviourInput.isRegistered(w, b, "LeftButton", "Down"), false)
    b:RegisterForClicks("RightButtonDown", "LeftButtonUp")
    A.eq(BehaviourInput.isRegistered(w, b, "RightButton", "Down"), true)
    A.eq(BehaviourInput.isRegistered(w, b, "RightButton", "Up"), false)
    A.eq(BehaviourInput.isRegistered(w, b, "LeftButton", "Up"), true)
  end)
end

local function test_click_on_a_disabled_button_does_nothing() -- (I3)
  withWidgets("retail", function()
    local b = _G.CreateFrame("Button")
    local log = Rec.record(b, { "PreClick", "OnClick", "PostClick" })
    b:Disable()
    b:Click()
    A.same(log, {})
  end)
end

local function test_click_skips_mouse_and_visibility_checks() -- (I3)
  withWidgets("retail", function()
    local b = _G.CreateFrame("Button")
    local log = Rec.record(b, { "OnClick" })
    b:EnableMouse(false)
    b:Hide()
    b:Click()
    A.eq(#log, 1)
  end)
end

local function test_enable_on_another_widget_type_keeps_the_generic_no_op()
  withWidgets("retail", function(w)
    _G.CreateFrame("Slider"):Enable()
    A.eq(w.unscripted["Slider:Enable"], 1)
  end)
end

local function test_set_checked_round_trips_and_fires_no_script()
  withWidgets("retail", function()
    local c = _G.CreateFrame("CheckButton")
    local log = Rec.record(c, { "OnClick" })
    c:SetChecked(true)
    A.eq(c:GetChecked(), true)
    c:SetChecked(false)
    A.eq(c:GetChecked(), false)
    A.same(log, {})
  end)
end

local function test_run_click_passes_down_true()
  withWidgets("retail", function(w)
    local b = _G.CreateFrame("Button")
    local log = Rec.record(b, { "PreClick", "OnClick", "PostClick" })
    BehaviourInput.runClick(w, b, "LeftButton", true)
    A.same(log, {
      { "PreClick", "LeftButton", true },
      { "OnClick", "LeftButton", true },
      { "PostClick", "LeftButton", true },
    })
  end)
end

local function test_set_focus_moves_focus_and_fires_lost_then_gained()
  withWidgets("retail", function(w)
    local a, b = _G.CreateFrame("EditBox"), _G.CreateFrame("EditBox")
    local log = Rec.record(a, { "OnEditFocusGained", "OnEditFocusLost" }, nil, "a")
    Rec.record(b, { "OnEditFocusGained", "OnEditFocusLost" }, log, "b")
    a:SetFocus()
    b:SetFocus()
    A.same(log, { { "a:OnEditFocusGained" }, { "a:OnEditFocusLost" }, { "b:OnEditFocusGained" } })
    A.eq(a:HasFocus(), false)
    A.eq(b:HasFocus(), true)
    A.eq(w.input.editFocus, b)
  end)
end

local function test_focus_state_is_current_when_the_handlers_run()
  withWidgets("retail", function()
    local a, b = _G.CreateFrame("EditBox"), _G.CreateFrame("EditBox")
    local seen = {}
    a:SetScript("OnEditFocusLost", function(self)
      seen.lost = self:HasFocus()
    end)
    b:SetScript("OnEditFocusGained", function(self)
      seen.gained = self:HasFocus()
    end)
    a:SetFocus()
    b:SetFocus()
    A.same(seen, { lost = false, gained = true })
  end)
end

local function test_set_focus_on_the_focused_box_fires_nothing()
  withWidgets("retail", function()
    local a = _G.CreateFrame("EditBox")
    local log = Rec.record(a, { "OnEditFocusGained", "OnEditFocusLost" })
    a:SetFocus()
    a:SetFocus()
    A.same(log, { { "OnEditFocusGained" } })
  end)
end

local function test_clear_focus_fires_lost_and_clears_only_for_the_focused_box()
  withWidgets("retail", function(w)
    local a, b = _G.CreateFrame("EditBox"), _G.CreateFrame("EditBox")
    local logA = Rec.record(a, { "OnEditFocusLost" })
    local logB = Rec.record(b, { "OnEditFocusLost" })
    a:SetFocus()
    b:ClearFocus()
    A.same(logB, {})
    A.eq(a:HasFocus(), true)
    a:ClearFocus()
    A.same(logA, { { "OnEditFocusLost" } })
    A.eq(w.input.editFocus, nil)
  end)
end

local function test_set_text_on_an_edit_box_fires_on_text_changed_with_user_input_false() -- (I6)
  withWidgets("retail", function()
    local box = _G.CreateFrame("EditBox")
    local log = Rec.record(box, { "OnTextSet", "OnTextChanged" })
    box:SetText("hi")
    A.eq(box:GetText(), "hi")
    A.same(log, { { "OnTextSet" }, { "OnTextChanged", false } }) -- (I6 confirmed: OnTextSet fires before OnTextChanged)
  end)
end

local function test_set_text_on_other_types_is_unchanged()
  withWidgets("retail", function()
    local fontString = _G.CreateFrame("Frame"):CreateFontString()
    fontString:SetText("x")
    A.eq(fontString:GetText(), "x")
    local button = _G.CreateFrame("Button")
    button:SetText("y")
    A.eq(button:GetText(), "y")
  end)
end

return function()
  test_set_focus_moves_focus_and_fires_lost_then_gained()
  test_focus_state_is_current_when_the_handlers_run()
  test_set_focus_on_the_focused_box_fires_nothing()
  test_clear_focus_fires_lost_and_clears_only_for_the_focused_box()
  test_set_text_on_an_edit_box_fires_on_text_changed_with_user_input_false()
  test_set_text_on_other_types_is_unchanged()
  test_widgets_install_creates_the_input_state()
  test_button_check_button_and_edit_box_start_mouse_enabled_assumed()
  test_mouse_scripts_enable_click_and_motion()
  test_enable_mouse_sets_click_and_motion_together()
  test_click_and_motion_are_set_separately()
  test_enable_mouse_motion_sets_motion_only()
  test_is_mouse_over_covers_descendants_and_motion_focus_is_exact()
  test_mouse_queries_are_not_counted_as_unscripted()
  test_disable_and_enable_fire_their_scripts_only_on_change_assumed()
  test_click_runs_the_three_scripts_with_button_and_down_false()
  test_click_passes_is_down_to_the_scripts()
  test_click_during_its_own_click_does_nothing()
  test_click_after_an_erroring_on_click_still_runs()
  test_nested_mouse_click_keeps_the_outer_click_in_progress()
  test_check_button_click_flips_the_state_before_the_scripts_assumed()
  test_register_for_clicks_defaults_to_left_button_up()
  test_register_for_clicks_accepts_any_and_named_types()
  test_click_on_a_disabled_button_does_nothing()
  test_click_skips_mouse_and_visibility_checks()
  test_enable_on_another_widget_type_keeps_the_generic_no_op()
  test_set_checked_round_trips_and_fires_no_script()
  test_run_click_passes_down_true()
end
