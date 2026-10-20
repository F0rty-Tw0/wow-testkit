-- Button input methods: enable state, clicks and click registration, CheckButton checked state.
local A = require("assert")
local BehaviourInput = require("ui.behaviour_input")
local HW = require("tests.helpers.widgets")
local Rec = require("tests.helpers.input")
local Widgets = require("ui.widgets")

local withWidgets = HW.withWidgets

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
    A.same(log, {
      { "PreClick", "RightButton", true },
      { "OnClick", "RightButton", true },
      { "PostClick", "RightButton", true },
    })
  end)
end

local function test_click_turns_a_non_boolean_is_down_into_a_boolean_assumed() -- (I3)
  withWidgets("retail", function()
    local b = _G.CreateFrame("Button")
    local log = Rec.record(b, { "OnClick" })
    b:Click("LeftButton", 1)
    A.same(log, { { "OnClick", "LeftButton", true } })
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

local function test_click_after_an_erroring_click_script_still_runs() -- (I3)
  for _, script in ipairs({ "PreClick", "OnClick", "PostClick" }) do
    withWidgets("retail", function(w)
      local b = _G.CreateFrame("Button")
      local clicks = 0
      b:SetScript(script, function()
        clicks = clicks + 1
        if clicks == 1 then
          error("boom")
        end
      end)
      b:Click()
      b:Click()
      A.eq(clicks, 2, script)
      A.eq(#w.errors, 1, script)
      A.contains(tostring(w.errors[1].message), "boom")
    end)
  end
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

local function test_click_after_an_erroring_intrinsic_click_handler_still_runs()
  for _, script in ipairs({ "PreClick", "OnClick", "PostClick" }) do
    withWidgets("retail", function(w)
      local clicks = 0
      Widgets.registerIntrinsic(w, "Pill", "Button", {
        scripts = {
          [script] = function()
            clicks = clicks + 1
            if clicks == 1 then
              error("kit boom", 0)
            end
          end,
        },
      })
      local pill = _G.CreateFrame("Pill")
      local message = A.errors(function()
        pill:Click()
      end)
      A.eq(message, "kit boom", script) -- re-raised as is, with no position of runClick's own
      pill:Click()
      A.eq(clicks, 2, script)
    end)
  end
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

local function test_click_skips_mouse_and_visibility_checks_assumed() -- (I3)
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

return function()
  test_disable_and_enable_fire_their_scripts_only_on_change_assumed()
  test_click_runs_the_three_scripts_with_button_and_down_false()
  test_click_passes_is_down_to_the_scripts()
  test_click_turns_a_non_boolean_is_down_into_a_boolean_assumed()
  test_click_during_its_own_click_does_nothing()
  test_click_after_an_erroring_click_script_still_runs()
  test_nested_mouse_click_keeps_the_outer_click_in_progress()
  test_click_after_an_erroring_intrinsic_click_handler_still_runs()
  test_check_button_click_flips_the_state_before_the_scripts_assumed()
  test_register_for_clicks_defaults_to_left_button_up()
  test_register_for_clicks_accepts_any_and_named_types()
  test_click_on_a_disabled_button_does_nothing()
  test_click_skips_mouse_and_visibility_checks_assumed()
  test_enable_on_another_widget_type_keeps_the_generic_no_op()
  test_set_checked_round_trips_and_fires_no_script()
  test_run_click_passes_down_true()
end
