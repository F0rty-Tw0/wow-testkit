-- Input actions and blocked reasons: the engine side of click, enter and leave.
local A = require("assert")
local Flavors = require("tools.flavors")
local HF = require("tests.helpers.framexml")
local Input = require("input")
local Rec = require("tests.helpers.input")

local withFrameXML = HF.withFrameXML
local CLICK_SCRIPTS = { "OnMouseDown", "OnMouseUp", "PreClick", "OnClick", "PostClick" }

local function newButton(name)
  return _G.CreateFrame("Button", name, _G.UIParent)
end

local function newBox(name)
  return _G.CreateFrame("EditBox", name, _G.UIParent)
end

local function test_blocked_reason_not_a_frame()
  withFrameXML("retail", function(w)
    A.eq(Input.blockedReason(w, nil, "click"), "not a frame")
    A.eq(Input.blockedReason(w, {}, "click"), "not a frame")
    A.eq(Input.blockedReason(w, _G.UIParent:CreateTexture(), "click"), "not a frame")
  end)
end

local function test_blocked_reason_names_the_first_hidden_frame_up_the_chain()
  withFrameXML("retail", function(w)
    local host = _G.CreateFrame("Frame", "Host", _G.UIParent)
    local button = _G.CreateFrame("Button", nil, host)
    host:Hide()
    A.eq(Input.blockedReason(w, button, "click"), "hidden: Host is not shown")
    host:Show()
    button:Hide()
    A.eq(Input.blockedReason(w, button, "enter"), "hidden: Button in Host is not shown")
  end)
end

local function test_blocked_reason_mouse_disabled_for_click_and_enter()
  withFrameXML("retail", function(w)
    A.eq(Input.blockedReason(w, _G.CreateFrame("Frame", nil, _G.UIParent), "click"), "mouse disabled")
    local button = newButton()
    button:SetMouseClickEnabled(false)
    A.eq(Input.blockedReason(w, button, "click"), "mouse disabled")
    A.eq(Input.blockedReason(w, button, "enter"), nil)
    button:SetMouseMotionEnabled(false)
    A.eq(Input.blockedReason(w, button, "enter"), "mouse disabled")
  end)
end

local function test_blocked_reason_disabled()
  withFrameXML("retail", function(w)
    local button = newButton()
    button:Disable()
    A.eq(Input.blockedReason(w, button, "click"), "disabled")
    A.eq(Input.blockedReason(w, button, "enter"), nil)
  end)
end

local function test_blocked_reason_not_registered_for_the_button()
  withFrameXML("retail", function(w)
    local button = newButton()
    button:RegisterForClicks("LeftButtonUp")
    A.eq(Input.blockedReason(w, button, "click", "RightButton"), "not registered for RightButton")
    A.eq(Input.blockedReason(w, button, "click"), nil)
  end)
end

local function test_blocked_reason_not_an_edit_box()
  withFrameXML("retail", function(w)
    A.eq(Input.blockedReason(w, newButton(), "type"), "not an EditBox")
    A.eq(Input.blockedReason(w, newBox(), "type"), nil)
  end)
end

local function test_blocked_reason_order()
  withFrameXML("retail", function(w)
    local plain = _G.CreateFrame("Frame", "Plain", _G.UIParent)
    plain:Hide()
    A.eq(Input.blockedReason(w, plain, "click"), "hidden: Plain is not shown")
    local button = newButton()
    button:Disable()
    button:RegisterForClicks("LeftButtonUp")
    A.eq(Input.blockedReason(w, button, "click", "RightButton"), "disabled")
  end)
end

local function test_unblocked_click_returns_nil()
  withFrameXML("retail", function(w)
    A.eq(Input.blockedReason(w, newButton(), "click"), nil)
  end)
end

local function test_is_frame_accepts_frames_only()
  withFrameXML("retail", function(w)
    A.eq(Input.isFrame(w, newButton()), true)
    A.eq(Input.isFrame(w, _G.UIParent:CreateTexture()), false)
    A.eq(Input.isFrame(w, {}), false)
    A.eq(Input.isFrame(w, "Button"), false)
  end)
end

local function test_click_runs_mouse_and_click_scripts_in_order_for_an_up_click() -- (I7)
  withFrameXML("retail", function(w)
    local b = newButton()
    local log = Rec.record(b, CLICK_SCRIPTS)
    Input.click(w, b, "LeftButton")
    A.same(log, {
      { "OnMouseDown", "LeftButton" },
      { "OnMouseUp", "LeftButton", true },
      { "PreClick", "LeftButton", false },
      { "OnClick", "LeftButton", false },
      { "PostClick", "LeftButton", false },
    })
  end)
end

local function test_click_with_down_and_up_registered_runs_down_clicks_first()
  withFrameXML("retail", function(w)
    local b = newButton()
    b:RegisterForClicks("AnyDown", "AnyUp")
    local log = Rec.record(b, CLICK_SCRIPTS)
    Input.click(w, b, "LeftButton")
    A.same(log, {
      { "OnMouseDown", "LeftButton" },
      { "PreClick", "LeftButton", true },
      { "OnClick", "LeftButton", true },
      { "PostClick", "LeftButton", true },
      { "OnMouseUp", "LeftButton", true },
      { "PreClick", "LeftButton", false },
      { "OnClick", "LeftButton", false },
      { "PostClick", "LeftButton", false },
    })
  end)
end

local function test_click_on_a_plain_frame_fires_only_the_mouse_scripts()
  withFrameXML("retail", function(w)
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    f:EnableMouse(true)
    local log = Rec.record(f, { "OnMouseDown", "OnMouseUp" })
    Input.click(w, f, "LeftButton")
    A.same(log, { { "OnMouseDown", "LeftButton" }, { "OnMouseUp", "LeftButton", true } })
  end)
end

local function test_click_flips_a_check_button_once_per_click()
  withFrameXML("retail", function(w)
    local c = _G.CreateFrame("CheckButton", nil, _G.UIParent)
    Input.click(w, c, "LeftButton")
    A.eq(c:GetChecked(), true)
    Input.click(w, c, "LeftButton")
    A.eq(c:GetChecked(), false)
  end)
end

local function test_click_handler_error_is_recorded_and_the_click_goes_on()
  withFrameXML("retail", function(w)
    local b = newButton()
    local log = Rec.record(b, { "PostClick" })
    b:SetScript("OnClick", function()
      error("boom")
    end)
    Input.click(w, b, "LeftButton")
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "boom")
    A.same(log, { { "PostClick", "LeftButton", false } })
  end)
end

local function test_enter_fires_on_enter_with_motion_true_and_sets_focus()
  withFrameXML("retail", function(w)
    local b = newButton()
    local log = Rec.record(b, { "OnEnter" })
    Input.enter(w, b)
    A.same(log, { { "OnEnter", true } })
    A.eq(w.input.mouseFocus, b)
  end)
end

local function test_enter_another_frame_leaves_the_previous_one_first()
  withFrameXML("retail", function(w)
    local a, b = newButton(), newButton()
    local log = Rec.record(a, { "OnEnter", "OnLeave" }, nil, "a")
    Rec.record(b, { "OnEnter", "OnLeave" }, log, "b")
    Input.enter(w, a)
    Input.enter(w, b)
    A.same(log, { { "a:OnEnter", true }, { "a:OnLeave", true }, { "b:OnEnter", true } })
    A.eq(w.input.mouseFocus, b)
  end)
end

local function test_leave_fires_on_leave_and_clears_focus()
  withFrameXML("retail", function(w)
    local b = newButton()
    local log = Rec.record(b, { "OnLeave" })
    Input.enter(w, b)
    Input.leave(w, b)
    A.same(log, { { "OnLeave", true } })
    A.eq(w.input.mouseFocus, nil)
  end)
end

local function test_leave_without_the_mouse_throws()
  withFrameXML("retail", function(w)
    local b = newButton("Other")
    A.errors(function()
      Input.leave(w, b)
    end, "leave: Other does not have the mouse")
  end)
end

local function test_focus_is_set_inside_on_enter_and_cleared_inside_on_leave_assumed() -- (I11)
  withFrameXML("retail", function(w)
    local b = newButton()
    local seen = {}
    b:SetScript("OnEnter", function(self)
      seen[#seen + 1] = self:IsMouseMotionFocus()
    end)
    b:SetScript("OnLeave", function(self)
      seen[#seen + 1] = self:IsMouseMotionFocus()
    end)
    Input.enter(w, b)
    Input.leave(w, b)
    A.same(seen, { true, false })
  end)
end

local function test_get_mouse_foci_returns_the_focus_or_an_empty_table() -- (I9)
  withFrameXML("retail", function(w)
    local b = newButton()
    A.same(_G.GetMouseFoci(), {})
    Input.enter(w, b)
    A.same(_G.GetMouseFoci(), { b })
    A.eq(w.unscripted.GetMouseFoci, nil)
  end)
end

local function test_get_mouse_foci_is_installed_on_every_flavor()
  for _, flavor in ipairs(Flavors.list) do
    withFrameXML(flavor, function()
      A.eq(type(_G.GetMouseFoci), "function")
      A.same(_G.GetMouseFoci(), {})
    end)
  end
end

local function test_get_mouse_focus_is_not_installed()
  withFrameXML("retail", function()
    A.eq(rawget(_G, "GetMouseFocus"), nil)
  end)
end

return function()
  test_blocked_reason_not_a_frame()
  test_blocked_reason_names_the_first_hidden_frame_up_the_chain()
  test_blocked_reason_mouse_disabled_for_click_and_enter()
  test_blocked_reason_disabled()
  test_blocked_reason_not_registered_for_the_button()
  test_blocked_reason_not_an_edit_box()
  test_blocked_reason_order()
  test_unblocked_click_returns_nil()
  test_is_frame_accepts_frames_only()
  test_click_runs_mouse_and_click_scripts_in_order_for_an_up_click()
  test_click_with_down_and_up_registered_runs_down_clicks_first()
  test_click_on_a_plain_frame_fires_only_the_mouse_scripts()
  test_click_flips_a_check_button_once_per_click()
  test_click_handler_error_is_recorded_and_the_click_goes_on()
  test_enter_fires_on_enter_with_motion_true_and_sets_focus()
  test_enter_another_frame_leaves_the_previous_one_first()
  test_leave_fires_on_leave_and_clears_focus()
  test_leave_without_the_mouse_throws()
  test_focus_is_set_inside_on_enter_and_cleared_inside_on_leave_assumed()
  test_get_mouse_foci_returns_the_focus_or_an_empty_table()
  test_get_mouse_foci_is_installed_on_every_flavor()
  test_get_mouse_focus_is_not_installed()
end
