-- Widget input methods: mouse state and mouse-over queries.
local A = require("assert")
local HW = require("tests.helpers.widgets")

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

return function()
  test_widgets_install_creates_the_input_state()
  test_button_check_button_and_edit_box_start_mouse_enabled_assumed()
  test_mouse_scripts_enable_click_and_motion()
  test_enable_mouse_sets_click_and_motion_together()
  test_click_and_motion_are_set_separately()
  test_enable_mouse_motion_sets_motion_only()
  test_is_mouse_over_covers_descendants_and_motion_focus_is_exact()
  test_mouse_queries_are_not_counted_as_unscripted()
end
