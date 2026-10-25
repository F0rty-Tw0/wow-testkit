-- Keyboard input: a key press reaches an EditBox with focus alone, else the keyboard-enabled frames topmost first until
-- one stops propagating, else the key's binding. Every rule is assumed (no client Lua or doc settles it).
local A = require("assert")
local H = require("tests.helpers.session")
local Keys = require("input_keys")

local DEMO_BINDINGS = H.DEMO .. "/demo-bindings.wtf"

local function text()
  return _G.SessionDemoText:GetText()
end

-- A keyboard frame at the screen centre that logs "<name>:down:<key>" and "<name>:up:<key>" into log.
local function keyFrame(name, level, propagate, log)
  local frame = _G.CreateFrame("Frame", name, _G.UIParent)
  frame:SetSize(10, 10)
  frame:SetPoint("CENTER")
  frame:SetFrameLevel(level)
  frame:EnableKeyboard(true)
  frame:SetPropagateKeyboardInput(propagate)
  frame:SetScript("OnKeyDown", function(_, key)
    log[#log + 1] = name .. ":down:" .. key
  end)
  frame:SetScript("OnKeyUp", function(_, key)
    log[#log + 1] = name .. ":up:" .. key
  end)

  return frame
end

-- source: assumed (K2) test_keydown_reaches_a_keyboard_frame
local function test_keydown_reaches_a_keyboard_frame_assumed()
  H.withSession(nil, function(sess)
    local reply = Keys.press(sess.w, "A", {})
    A.eq(text(), "key:A")
    A.eq(reply.consumedBy, nil)
  end)
end

-- source: assumed (K2) test_propagating_frames_pass_the_key_down
local function test_propagating_frames_pass_the_key_down_assumed()
  H.withSession(nil, function(sess)
    local log = {}
    keyFrame("KeysAbove", 50, true, log)
    Keys.press(sess.w, "A", {})
    A.eq(text(), "key:A", "the lower frame still sees the key")
    A.same(log, { "KeysAbove:down:A", "KeysAbove:up:A" })
  end)
end

-- source: assumed (K2) test_a_non_propagating_frame_swallows_the_key
local function test_a_non_propagating_frame_swallows_the_key_assumed()
  H.withSession({ bindingsFile = DEMO_BINDINGS }, function(sess)
    local log = {}
    local modal = keyFrame("KeysModal", 50, false, log)
    local reply = Keys.press(sess.w, "K", {})
    A.same(log, { "KeysModal:down:K", "KeysModal:up:K" })
    A.eq(text(), "idle", "neither the lower frame nor the binding ran")
    A.eq(reply.consumedBy, modal)
    A.eq(reply.binding, nil)
  end)
end

-- source: assumed (K2) a handler may turn propagation off for the frames below it.
local function test_a_handler_can_stop_propagation_assumed()
  H.withSession(nil, function(sess)
    local log = {}
    local frame = keyFrame("KeysStops", 50, true, log)
    frame:SetScript("OnKeyDown", function(self)
      self:SetPropagateKeyboardInput(false)
    end)
    Keys.press(sess.w, "A", {})
    A.eq(text(), "idle")
  end)
end

-- source: assumed (K1) test_edit_box_focus_swallows_everything
local function test_edit_box_focus_swallows_everything_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local log = {}
    keyFrame("KeysOther", 50, true, log)
    local box = _G.ClickyBox
    box:SetScript("OnKeyDown", function(_, key)
      log[#log + 1] = "box:down:" .. key
    end)
    box:SetScript("OnKeyUp", function(_, key)
      log[#log + 1] = "box:up:" .. key
    end)
    box:SetFocus()
    local reply = Keys.press(sess.w, "X", {})
    A.same(log, { "box:down:X", "box:up:X" })
    A.eq(reply.consumedBy, box)
    Keys.press(sess.w, "ENTER", {})
    A.same(sess.s.ns.log, { "ClickyBox:enter-pressed:" })
  end)
end

-- source: assumed (K1) a focused box that is hidden takes no key; the frames below get it.
local function test_a_hidden_focused_box_takes_no_key_assumed()
  H.withSession(nil, function(sess)
    local box = _G.CreateFrame("EditBox", "KeysHiddenBox", _G.UIParent)
    box:Hide()
    box:SetFocus()
    local reply = Keys.press(sess.w, "A", {})
    A.eq(reply.consumedBy, nil)
    A.eq(text(), "key:A")
  end)
end

-- source: assumed (K1) hiding the focused box hands the keys back to the frames.
local function test_hiding_the_focused_box_hands_keys_back_assumed()
  H.withSession(nil, function(sess)
    local box = _G.CreateFrame("EditBox", "KeysShownBox", _G.UIParent)
    box:SetFocus()
    box:Hide()
    A.eq(box:HasFocus(), false)
    Keys.press(sess.w, "A", {})
    A.eq(text(), "key:A")
  end)
end

-- source: assumed (K1) test_backspace_removes_the_last_character
local function test_backspace_removes_the_last_character_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local box = _G.ClickyBox
    require("input").type(sess.w, box, "hi")
    sess.s.ns.log = {}
    Keys.press(sess.w, "BACKSPACE", {})
    A.eq(box:GetText(), "h")
    A.same(sess.s.ns.log, { "ClickyBox:text:h:true" })
  end)
end

local function test_backspace_removes_a_multibyte_character_whole_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local box = _G.ClickyBox
    require("input").type(sess.w, box, "h\195\169")
    Keys.press(sess.w, "BACKSPACE", {})
    A.eq(box:GetText(), "h")
    Keys.press(sess.w, "BACKSPACE", {})
    Keys.press(sess.w, "BACKSPACE", {})
    A.eq(box:GetText(), "")
  end)
end

-- source: assumed (K2) test_hidden_or_keyboard_disabled_frames_get_nothing
local function test_hidden_or_keyboard_disabled_frames_get_nothing_assumed()
  H.withSession(nil, function(sess)
    local log = {}
    keyFrame("KeysHidden", 50, false, log):Hide()
    keyFrame("KeysOff", 51, false, log):EnableKeyboard(false)
    Keys.press(sess.w, "A", {})
    A.same(log, {})
    A.eq(text(), "key:A", "the visible keyboard frame below still got the key")
  end)
end

-- source: assumed (K2) a hidden parent hides its keyboard children too.
local function test_a_frame_under_a_hidden_parent_gets_nothing_assumed()
  H.withSession(nil, function(sess)
    local log = {}
    local child = keyFrame("KeysChild", 50, false, log)
    child:SetParent(_G.SessionDemoHidden)
    Keys.press(sess.w, "A", {})
    A.same(log, {})
  end)
end

-- source: assumed (K3) test_combination_orders_modifiers
local function test_combination_orders_modifiers_assumed()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    _G.SetBindingClick("CTRL-SHIFT-K", "ClickyCheck")
    local reply = Keys.press(sess.w, "K", { shift = true, ctrl = true })
    A.eq(reply.binding, "CLICK ClickyCheck:LeftButton")
    A.same(sess.s.ns.log, { "ClickyCheck:click:checked=true" })
    A.eq(Keys.press(sess.w, "K", { ctrl = true, shift = true, alt = true }).binding, nil)
  end)
end

return function()
  test_keydown_reaches_a_keyboard_frame_assumed()
  test_propagating_frames_pass_the_key_down_assumed()
  test_a_non_propagating_frame_swallows_the_key_assumed()
  test_a_handler_can_stop_propagation_assumed()
  test_edit_box_focus_swallows_everything_assumed()
  test_a_hidden_focused_box_takes_no_key_assumed()
  test_hiding_the_focused_box_hands_keys_back_assumed()
  test_backspace_removes_the_last_character_assumed()
  test_backspace_removes_a_multibyte_character_whole_assumed()
  test_hidden_or_keyboard_disabled_frames_get_nothing_assumed()
  test_a_frame_under_a_hidden_parent_gets_nothing_assumed()
  test_combination_orders_modifiers_assumed()
end
