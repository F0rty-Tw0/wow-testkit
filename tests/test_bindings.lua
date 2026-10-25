-- Key bindings: the user's bindings-cache.wtf lines, an addon's Bindings.xml bodies, the SetBinding family and what a
-- key press runs. Blizzard's own Bindings.xml is not loaded here.
local A = require("assert")
local Bindings = require("bindings")
local H = require("tests.helpers.session")
local Keys = require("input_keys")

local DEMO_BINDINGS = H.DEMO .. "/demo-bindings.wtf"

local function text()
  return _G.SessionDemoText:GetText()
end

local function test_wtf_lines_bind_keys()
  H.withSession({ bindingsFile = DEMO_BINDINGS }, function()
    A.eq(_G.GetBindingAction("K"), "SESSIONDEMO_TOGGLE")
    A.eq(_G.GetBindingKey("SESSIONDEMO_TOGGLE"), "K")
    A.eq(_G.GetBindingAction("J"), "")
  end)
end

local function test_wtf_ignores_other_lines_and_lists_every_key()
  H.withSession(nil, function(sess)
    Bindings.loadWtf(sess.w, "# comment\nset foo bar\nbind K ONE\r\nbind CTRL-K ONE\nbind\nbind J\n")
    local first, second, third = _G.GetBindingKey("ONE")
    A.same({ first, second, third }, { "CTRL-K", "K" })
    A.eq(_G.GetBindingAction("J"), "")
  end)
end

local function test_xml_binding_runs_its_body_with_keystate()
  H.withSession({ bindingsFile = DEMO_BINDINGS }, function(sess)
    local reply = Keys.press(sess.w, "K", {})
    A.eq(text(), "binding:down")
    A.eq(reply.binding, "SESSIONDEMO_TOGGLE")
  end)
end

local function test_run_on_up_attribute_runs_on_key_up_only()
  local up = '<Binding name="UP_TEST" runOnUp="true">UpTestLog = (UpTestLog or "") .. keystate .. ";"</Binding>'
  local down = '<Binding name="DOWN_TEST">DownTestLog = (DownTestLog or "") .. keystate .. ";"</Binding>'
  local xml = "<Bindings>" .. up .. down .. "</Bindings>"
  local root = H.tempAddon("BindUp", "-- the bodies live in Bindings.xml", { ["Bindings.xml"] = xml })
  H.withSession({ addonDir = root }, function(sess)
    _G.SetBinding("U", "UP_TEST")
    _G.SetBinding("D", "DOWN_TEST")
    Keys.press(sess.w, "U", {})
    Keys.press(sess.w, "D", {})
    A.eq(_G.UpTestLog, "up;")
    A.eq(_G.DownTestLog, "down;")
  end)
end

local function test_click_binding_clicks_the_frame()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    _G.SetBindingClick("J", "ClickyCheck")
    A.eq(_G.GetBindingAction("J"), "CLICK ClickyCheck:LeftButton")
    Keys.press(sess.w, "J", {})
    A.same(sess.s.ns.log, { "ClickyCheck:click:checked=true" })
  end)
end

local function test_set_binding_without_command_unbinds()
  H.withSession({ bindingsFile = DEMO_BINDINGS }, function(sess)
    A.eq(_G.SetBinding("K"), true)
    A.eq(_G.GetBindingAction("K"), "")
    A.eq(_G.GetBindingKey("SESSIONDEMO_TOGGLE"), nil)
    Keys.press(sess.w, "K", {})
    A.eq(text(), "key:K", "only the keyboard frame ran")
  end)
end

local function test_override_binding_wins_and_clears()
  H.withSession({ bindingsFile = DEMO_BINDINGS }, function(sess)
    local owner = _G.SessionDemoFrame
    _G.SetOverrideBinding(owner, true, "K", "OTHER")
    A.eq(_G.GetBindingAction("K", true), "OTHER")
    A.eq(_G.GetBindingAction("K"), "SESSIONDEMO_TOGGLE", "a plain query ignores overrides")
    A.eq(Keys.press(sess.w, "K", {}).binding, "OTHER")
    A.eq(text(), "key:K", "the plain binding did not run")
    _G.ClearOverrideBindings(owner)
    Keys.press(sess.w, "K", {})
    A.eq(text(), "binding:down")
  end)
end

local function test_a_priority_override_beats_a_plain_override()
  H.withSession(nil, function()
    local first, second = _G.SessionDemoFrame, _G.SessionDemoButton
    _G.SetOverrideBinding(first, true, "K", "PRIORITY")
    _G.SetOverrideBinding(second, false, "K", "PLAIN")
    A.eq(_G.GetBindingAction("K", true), "PRIORITY")
    _G.SetOverrideBindingClick(first, false, "K", "SessionDemoButton")
    A.eq(_G.GetBindingAction("K", true), "CLICK SessionDemoButton:LeftButton")
    _G.ClearOverrideBindings(first)
    A.eq(_G.GetBindingAction("K", true), "PLAIN")
  end)
end

local function test_blocked_click_binding_does_nothing()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    _G.ClickyButton:Disable()
    _G.SetBindingClick("B", "ClickyButton")
    _G.SetBindingClick("N", "NoSuchFrame")
    Keys.press(sess.w, "B", {})
    Keys.press(sess.w, "N", {})
    A.same(sess.s.ns.log, {})
    A.same(sess.w.errors, {})
  end)
end

return function()
  test_wtf_lines_bind_keys()
  test_wtf_ignores_other_lines_and_lists_every_key()
  test_xml_binding_runs_its_body_with_keystate()
  test_run_on_up_attribute_runs_on_key_up_only()
  test_click_binding_clicks_the_frame()
  test_set_binding_without_command_unbinds()
  test_override_binding_wins_and_clears()
  test_a_priority_override_beats_a_plain_override()
  test_blocked_click_binding_does_nothing()
end
