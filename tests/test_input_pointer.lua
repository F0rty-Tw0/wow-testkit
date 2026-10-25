-- Wheel and drag on SessionDemo (screen 1920x1080, scale 1) and Clicky: which frame gets the wheel, and the order of
-- the scripts a drag runs. SessionDemoDrag is 100x100 at CENTER (-300, 0), so its centre is 660, 540 and its rect
-- x 610..710, y 490..590; SessionDemoWheel is 100x100 at CENTER (300, 0), centre 1260, 540. Every rule is assumed.
local A = require("assert")
local H = require("tests.helpers.session")
local Pointer = require("input_pointer")
local Rec = require("tests.helpers.input")

local DRAG_CENTRE = { x = 660, y = 540 }
local CLICKY_BUTTON = { x = 960, y = 490 }

local function text()
  return _G.SessionDemoText:GetText()
end

local function drag(sess, spec)
  return Pointer.drag(sess.w, spec)
end

-- source: assumed (W1) test_wheel_reaches_the_topmost_wheel_frame
local function test_wheel_reaches_the_topmost_wheel_frame_assumed()
  H.withSession(nil, function(sess)
    A.eq(Pointer.wheel(sess.w, 1260, 540, 1), _G.SessionDemoWheel)
    A.eq(text(), "wheel:1")
    Pointer.wheel(sess.w, 1260, 540, -1)
    A.eq(text(), "wheel:0")
    A.eq(Pointer.wheel(sess.w, 100, 100, 1), nil)
    A.eq(text(), "wheel:0")
  end)
end

local function test_wheel_prefers_the_higher_frame_and_skips_hidden_ones_assumed()
  H.withSession(nil, function(sess)
    local log = {}
    local above = _G.CreateFrame("Frame", "WheelAbove", _G.UIParent)
    above:SetAllPoints(_G.SessionDemoWheel)
    above:SetFrameLevel(50)
    above:EnableMouseWheel(true)
    above:SetScript("OnMouseWheel", function(_, delta)
      log[#log + 1] = delta
    end)
    A.eq(Pointer.wheel(sess.w, 1260, 540, 1), above)
    above:Hide()
    A.eq(Pointer.wheel(sess.w, 1260, 540, 1), _G.SessionDemoWheel)
    A.same(log, { 1 })
  end)
end

-- source: assumed (D3) test_drag_moves_a_movable_frame
local function test_drag_moves_a_movable_frame_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    A.eq(frame:GetLeft(), 610)
    A.eq(frame:GetBottom(), 490)
    local reply = drag(sess, { from = DRAG_CENTRE, to = { x = 760, y = 590 } })
    A.eq(reply.ok, true)
    A.eq(reply.frame, frame)
    A.eq(frame:GetLeft(), 710)
    A.eq(frame:GetBottom(), 440)
    A.same({ frame:GetPoint(1) }, { "BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 710, 440 })
    A.eq(sess.w.input.moving, nil, "OnDragStop ended the move")
  end)
end

-- source: assumed (D3) a move of exactly the threshold distance drags, one pixel less does not.
local function test_the_drag_threshold_is_four_pixels_assumed()
  H.withSession(nil, function(sess)
    drag(sess, { from = DRAG_CENTRE, to = { x = 663, y = 540 } })
    A.eq(_G.SessionDemoDrag:GetLeft(), 610)
    drag(sess, { from = DRAG_CENTRE, to = { x = 664, y = 540 } })
    A.eq(_G.SessionDemoDrag:GetLeft(), 614)
    drag(sess, { from = { x = 664, y = 540 }, to = { x = 667, y = 544 } })
    A.eq(_G.SessionDemoDrag:GetLeft(), 617, "3 right and 4 down is 5 px: a drag")
  end)
end

-- source: assumed (D4) test_drag_below_the_threshold_is_a_click
local function test_drag_below_the_threshold_is_a_click_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local button = _G.ClickyButton
    local dragged = {}
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
      dragged[#dragged + 1] = "start"
    end)
    drag(sess, { from = CLICKY_BUTTON, to = { x = 963, y = 490 } })
    A.same(sess.s.ns.log, { "ClickyButton:click:LeftButton:false" })
    A.same(dragged, {})
  end)
end

-- source: assumed (D4) test_drag_without_registration_does_not_click_when_released_elsewhere
local function test_drag_without_registration_does_not_click_when_released_elsewhere_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local log = Rec.record(_G.ClickyButton, { "OnMouseDown", "OnMouseUp", "OnDragStart" })
    drag(sess, { from = CLICKY_BUTTON, to = { x = 1500, y = 900 } })
    A.same(log, { { "OnMouseDown", "LeftButton" }, { "OnMouseUp", "LeftButton", false } })
    A.same(sess.s.ns.log, {})
  end)
end

-- source: assumed (D4) a drag that ends inside the same unregistered frame is a click.
local function test_drag_inside_an_unregistered_frame_is_a_click_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    drag(sess, { from = CLICKY_BUTTON, to = { x = 990, y = 500 } })
    A.same(sess.s.ns.log, { "ClickyButton:click:LeftButton:false" })
  end)
end

-- source: assumed (D4) a frame that StartMoving's in OnMouseDown follows the cursor without RegisterForDrag.
local function test_start_moving_on_mouse_down_follows_the_cursor_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    frame:RegisterForDrag()
    frame:SetScript("OnMouseDown", frame.StartMoving)
    frame:SetScript("OnMouseUp", frame.StopMovingOrSizing)
    drag(sess, { from = DRAG_CENTRE, to = { x = 960, y = 540 } })
    A.eq(frame:GetLeft(), 910, "released outside the old rect")
    drag(sess, { from = { x = 960, y = 540 }, to = { x = 980, y = 540 } })
    A.eq(frame:GetLeft(), 930, "released inside it")
  end)
end

local function test_a_drag_from_empty_space_does_nothing_assumed()
  H.withSession(nil, function(sess)
    local reply = drag(sess, { from = { x = 100, y = 100 }, to = { x = 300, y = 300 } })
    A.eq(reply.ok, true)
    A.eq(reply.frame, nil)
  end)
end

local function test_a_blocked_drag_replies_with_the_reason_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    _G.ClickyButton:Disable()
    local reply = drag(sess, { from = CLICKY_BUTTON, to = { x = 1500, y = 900 } })
    A.eq(reply.ok, false)
    A.eq(reply.reason, "disabled")
    A.same(sess.s.ns.log, {})
  end)
end

-- source: assumed (D3) test_not_movable_frames_do_not_move
local function test_not_movable_frames_do_not_move_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    frame:SetMovable(false)
    drag(sess, { from = DRAG_CENTRE, to = { x = 760, y = 590 } })
    A.eq(frame:GetLeft(), 610)
    A.eq(frame:GetBottom(), 490)
    A.eq(frame:GetPoint(1), "CENTER")
  end)
end

-- source: assumed (D3, LY14) test_drag_keeps_a_clamped_frame_on_screen
local function test_drag_keeps_a_clamped_frame_on_screen_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    frame:SetClampedToScreen(true)
    drag(sess, { from = DRAG_CENTRE, to = { x = 0, y = 540 } })
    A.eq(frame:GetLeft(), 0)
    A.eq(select(4, frame:GetPoint(1)), -50, "the offset is stored as given")
  end)
end

-- source: assumed (D3) test_start_sizing_changes_the_size
local function test_start_sizing_changes_the_size_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    frame:SetResizable(true)
    frame:SetScript("OnDragStart", function(self)
      self:StartSizing()
    end)
    drag(sess, { from = DRAG_CENTRE, to = { x = 700, y = 570 } })
    A.same({ frame:GetWidth(), frame:GetHeight() }, { 140, 130 })
    A.same({ frame:GetLeft(), frame:GetTop() }, { 610, 590 }, "the top left corner stays")
  end)
end

local function test_start_sizing_from_the_top_left_moves_the_origin_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    frame:SetResizable(true)
    frame:SetScript("OnDragStart", function(self)
      self:StartSizing("TOPLEFT")
    end)
    drag(sess, { from = DRAG_CENTRE, to = { x = 640, y = 520 } })
    A.same({ frame:GetWidth(), frame:GetHeight() }, { 120, 120 })
    A.same({ frame:GetRight(), frame:GetBottom() }, { 710, 490 }, "the bottom right corner stays")
  end)
end

local function test_a_frame_that_is_not_resizable_keeps_its_size_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    frame:SetScript("OnDragStart", function(self)
      self:StartSizing()
    end)
    drag(sess, { from = DRAG_CENTRE, to = { x = 700, y = 570 } })
    A.same({ frame:GetWidth(), frame:GetHeight() }, { 100, 100 })
  end)
end

-- source: assumed (D5) test_carry_gives_the_target_on_receive_drag
local function test_carry_gives_the_target_on_receive_drag_assumed()
  local onto = { x = 960, y = 600 }
  H.withSession(nil, function(sess)
    local log = Rec.record(_G.SessionDemoButton, { "OnReceiveDrag" })
    drag(sess, { from = DRAG_CENTRE, to = onto })
    A.same(log, {}, "nothing is carried")
  end)
  H.withSession(nil, function(sess)
    local log = Rec.record(_G.SessionDemoButton, { "OnReceiveDrag" })
    drag(sess, { from = DRAG_CENTRE, to = onto, carry = true })
    A.same(log, { { "OnReceiveDrag" } })
  end)
end

-- source: assumed (D3) test_drag_events_order
local function test_drag_events_order_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    local log = Rec.record(frame, { "OnMouseDown", "OnDragStart", "OnDragStop", "OnMouseUp", "OnReceiveDrag" })
    drag(sess, { from = DRAG_CENTRE, to = { x = 760, y = 590 }, button = "LeftButton" })
    A.same(log, {
      { "OnMouseDown", "LeftButton" },
      { "OnDragStart", "LeftButton" },
      { "OnDragStop" },
      { "OnMouseUp", "LeftButton", true },
    })
  end)
end

local function test_a_button_the_frame_is_not_registered_for_does_not_drag_assumed()
  H.withSession(nil, function(sess)
    local frame = _G.SessionDemoDrag
    drag(sess, { from = DRAG_CENTRE, to = { x = 760, y = 590 }, button = "RightButton" })
    A.eq(frame:GetLeft(), 610)
  end)
end

local function test_input_requests_reach_keys_wheel_and_drag()
  H.withSession({ bindingsFile = H.DEMO .. "/demo-bindings.wtf" }, function(sess)
    local pressed = sess:call("input", { kind = "press", key = "K", mods = {} })
    A.eq(pressed.ok, true)
    A.eq(pressed.binding, "SESSIONDEMO_TOGGLE")
    A.eq(text(), "binding:down")
    local wheeled = sess:call("input", { kind = "wheel", target = { x = 1260, y = 540 }, delta = 1 })
    A.eq(wheeled.target.name, "SessionDemoWheel")
    A.eq(text(), "wheel:1")
    local seq = sess.seq
    local dragged = sess:call("input", { kind = "drag", from = DRAG_CENTRE, to = { x = 760, y = 590 } })
    A.eq(dragged.target.name, "SessionDemoDrag")
    A.eq(_G.SessionDemoDrag:GetLeft(), 710)
    A.eq(sess.seq, seq + 1)
    local rect = H.item(sess:call("snapshot"), "SessionDemoDrag").rect
    A.same({ rect.x, rect.y }, { 710, 540 })
  end)
end

local function test_malformed_pointer_requests_reply_with_an_error()
  H.withSession(nil, function(sess)
    A.eq(sess:call("input", { kind = "wheel", delta = 1 }).ok, false)
    A.eq(sess:call("input", { kind = "wheel", target = { x = 1, y = 1 } }).ok, false)
    A.eq(sess:call("input", { kind = "drag", from = { x = 1, y = 1 } }).ok, false)
    A.eq(sess:call("input", { kind = "drag", from = { x = 1 }, to = { x = 1, y = 1 } }).ok, false)
    A.eq(sess:call("input", { kind = "press" }).ok, false)
    A.eq(sess:call("input", { kind = "press", key = "A", mods = "ctrl" }).ok, false)
  end)
end

return function()
  test_wheel_reaches_the_topmost_wheel_frame_assumed()
  test_wheel_prefers_the_higher_frame_and_skips_hidden_ones_assumed()
  test_drag_moves_a_movable_frame_assumed()
  test_the_drag_threshold_is_four_pixels_assumed()
  test_drag_below_the_threshold_is_a_click_assumed()
  test_drag_without_registration_does_not_click_when_released_elsewhere_assumed()
  test_drag_inside_an_unregistered_frame_is_a_click_assumed()
  test_start_moving_on_mouse_down_follows_the_cursor_assumed()
  test_a_drag_from_empty_space_does_nothing_assumed()
  test_a_blocked_drag_replies_with_the_reason_assumed()
  test_not_movable_frames_do_not_move_assumed()
  test_drag_keeps_a_clamped_frame_on_screen_assumed()
  test_start_sizing_changes_the_size_assumed()
  test_start_sizing_from_the_top_left_moves_the_origin_assumed()
  test_a_frame_that_is_not_resizable_keeps_its_size_assumed()
  test_carry_gives_the_target_on_receive_drag_assumed()
  test_drag_events_order_assumed()
  test_a_button_the_frame_is_not_registered_for_does_not_drag_assumed()
  test_input_requests_reach_keys_wheel_and_drag()
  test_malformed_pointer_requests_reply_with_an_error()
end
