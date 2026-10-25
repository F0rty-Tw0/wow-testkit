-- Session input at screen points (physical pixels, origin top-left) on Clicky. Its 200x120 panel sits at the centre
-- of 1920x1080, so x 860..1060, y 480..600: ClickyButton (80x24 TOP) x 920..1000, y 480..504; ClickyCheck (24x24
-- CENTER) x 948..972, y 528..552; ClickyBox (120x24 BOTTOM) x 900..1020, y 576..600. The panel is not mouse-enabled.
local A = require("assert")
local H = require("tests.helpers.session")

local BUTTON = { x = 960, y = 490 }
local CHECK = { x = 960, y = 540 }
local BOX = { x = 960, y = 588 }
local EMPTY = { x = 1500, y = 900 }

local function input(sess, req)
  return sess:call("input", req)
end

local function tail(log, n)
  local out = {}
  for i = #log - n + 1, #log do
    out[#out + 1] = log[i]
  end

  return out
end

local function test_enter_point_hovers_the_topmost_frame()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local reply = input(sess, { kind = "enter", target = BUTTON })
    A.eq(reply.ok, true)
    A.eq(reply.target.name, "ClickyButton")
    A.eq(reply.target.id, H.id(sess, "ClickyButton"))
    A.same(sess.s.ns.log, { "ClickyButton:enter:true" })
  end)
end

local function test_moving_between_frames_leaves_then_enters()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    input(sess, { kind = "enter", target = BUTTON })
    A.eq(input(sess, { kind = "enter", target = CHECK }).target.name, "ClickyCheck")
    A.same(sess.s.ns.log, { "ClickyButton:enter:true", "ClickyButton:leave:true", "ClickyCheck:enter:true" })
  end)
end

local function test_moving_within_the_hovered_frame_runs_no_script()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    input(sess, { kind = "enter", target = BUTTON })
    local seq = sess.seq
    A.eq(input(sess, { kind = "enter", target = { x = 930, y = 500 } }).ok, true)
    A.same(sess.s.ns.log, { "ClickyButton:enter:true" })
    A.eq(sess.seq, seq)
  end)
end

local function test_empty_space_leaves_the_hovered_frame()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    input(sess, { kind = "enter", target = BUTTON })
    local reply = input(sess, { kind = "enter", target = EMPTY })
    A.eq(reply.ok, true)
    A.eq(reply.target, nil)
    A.same(sess.s.ns.log, { "ClickyButton:enter:true", "ClickyButton:leave:true" })
    A.eq(input(sess, { kind = "leave" }).ok, true)
  end)
end

local function test_leave_without_a_target_leaves_the_hovered_frame()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    input(sess, { kind = "enter", target = CHECK })
    local reply = input(sess, { kind = "leave" })
    A.eq(reply.ok, true)
    A.eq(reply.target.name, "ClickyCheck")
    A.same(sess.s.ns.log, { "ClickyCheck:enter:true", "ClickyCheck:leave:true" })
  end)
end

local function test_a_frame_without_mouse_motion_is_not_entered()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    input(sess, { kind = "enter", target = CHECK })
    _G.ClickyButton:SetMouseMotionEnabled(false)
    local reply = input(sess, { kind = "enter", target = BUTTON })
    A.eq(reply.ok, false)
    A.eq(reply.reason, "mouse disabled")
    A.same(sess.s.ns.log, { "ClickyCheck:enter:true", "ClickyCheck:leave:true" })
  end)
end

local function test_click_point_hovers_then_clicks()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local reply = input(sess, { kind = "click", target = CHECK })
    A.eq(reply.ok, true)
    A.eq(reply.target.name, "ClickyCheck")
    A.same(sess.s.ns.log, { "ClickyCheck:enter:true", "ClickyCheck:click:checked=true" })
  end)
end

local function test_click_point_on_a_disabled_button_replies_the_reason()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    _G.ClickyButton:Disable()
    local reply = input(sess, { kind = "click", target = BUTTON })
    A.eq(reply.ok, false)
    A.eq(reply.reason, "disabled")
    A.eq(reply.target.name, "ClickyButton")
  end)
end

local function test_click_point_on_the_panel_alone_hits_nothing()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local reply = input(sess, { kind = "click", target = { x = 870, y = 490 } })
    A.eq(reply.ok, true)
    A.eq(reply.target, nil)
    A.same(sess.s.ns.log, {})
  end)
end

-- source: assumed (P3) a click on an EditBox gives it the keyboard focus.
local function test_click_on_an_edit_box_focuses_it_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    A.eq(input(sess, { kind = "click", target = BOX }).target.name, "ClickyBox")
    A.eq(_G.ClickyBox:HasFocus(), true)
    local typed = input(sess, { kind = "type", text = "hi" })
    A.eq(typed.ok, true)
    A.eq(typed.target.name, "ClickyBox")
    A.same(tail(sess.s.ns.log, 1), { "ClickyBox:text:hi:true" })
    A.eq(input(sess, { kind = "press", key = "ENTER" }).ok, true)
    A.same(tail(sess.s.ns.log, 1), { "ClickyBox:enter-pressed:hi" })
    _G.ClickyBox:ClearFocus()
    A.eq(input(sess, { kind = "type", text = "x" }).reason, "no focused EditBox")
    local unfocused = input(sess, { kind = "press", key = "ENTER" })
    A.same({ unfocused.ok, unfocused.reason, unfocused.target }, { true, nil, nil }, "a key press needs no focus")
  end)
end

-- source: assumed (K3) test_a_press_holds_its_modifiers_while_it_runs
local function test_a_press_holds_its_modifiers_while_it_runs_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local seen = {}
    local frame = _G.CreateFrame("Frame", "ModsFrame", _G.UIParent)
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function()
      seen[#seen + 1] = tostring(_G.IsShiftKeyDown()) .. "/" .. tostring(_G.IsControlKeyDown())
    end)
    input(sess, { kind = "press", key = "A", mods = { shift = true } })
    A.same(seen, { "true/false" })
    A.eq(_G.IsShiftKeyDown(), false, "the press's shift is released afterwards")
    sess:call("state", { modifiers = { ctrl = true } })
    input(sess, { kind = "press", key = "A", mods = {} })
    A.same(seen, { "true/false", "false/false" })
    A.eq(_G.IsControlKeyDown(), true, "the state's ctrl comes back")
  end)
end

-- source: assumed (K3) a SHIFT binding's action sees shift held
local function test_a_shift_binding_sees_shift_held_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local shift
    _G.ClickyCheck:SetScript("PostClick", function()
      shift = _G.IsShiftKeyDown()
    end)
    _G.SetBindingClick("SHIFT-K", "ClickyCheck")
    local reply = input(sess, { kind = "press", key = "K", mods = { shift = true } })
    A.eq(reply.binding, "CLICK ClickyCheck:LeftButton")
    A.eq(shift, true)
  end)
end

local function test_a_point_target_without_numbers_is_malformed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    A.contains(input(sess, { kind = "click", target = { x = "1" } }).error, "x and y")
    A.contains(input(sess, { kind = "enter" }).error, "target")
  end)
end

return function()
  test_enter_point_hovers_the_topmost_frame()
  test_moving_between_frames_leaves_then_enters()
  test_moving_within_the_hovered_frame_runs_no_script()
  test_empty_space_leaves_the_hovered_frame()
  test_leave_without_a_target_leaves_the_hovered_frame()
  test_a_frame_without_mouse_motion_is_not_entered()
  test_click_point_hovers_then_clicks()
  test_click_point_on_a_disabled_button_replies_the_reason()
  test_click_point_on_the_panel_alone_hits_nothing()
  test_click_on_an_edit_box_focuses_it_assumed()
  test_a_press_holds_its_modifiers_while_it_runs_assumed()
  test_a_shift_binding_sees_shift_held_assumed()
  test_a_point_target_without_numbers_is_malformed()
end
