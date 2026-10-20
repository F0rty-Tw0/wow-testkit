-- Hand-written widget input semantics: mouse state, mouse-over queries, and the SetScript wrapper that applies the
-- mouse-script auto-enable rule. M.methods are fn(w, obj, st, ...) like ui/behaviour.lua; M.typed[name] =
-- function(plan) -> impl | nil picks a type-specific body when the class is built (ui/widgets.lua classFor).
local M = {}

local BehaviourScripts = require("ui.behaviour_scripts")

local methods = {}
M.methods = methods
M.typed = {}

-- Scripts whose assignment implies EnableMouse(true).
local MOUSE_SCRIPTS = { OnEnter = true, OnLeave = true, OnMouseDown = true, OnMouseUp = true }

-- A method body for the types whose plan.isA has the given (lowercase) ancestor, else nil (falls back).
function M.onlyFor(isA, impl)
  return function(plan)
    if plan.isA[isA] then
      return impl
    end
  end
end

-- nil in st.mouseClick / st.mouseMotion means the type default: on for buttons and edit boxes, else off.
local function mouseState(st, key)
  local value = st[key]
  if value == nil then
    return st.plan.isA.button == true or st.plan.isA.editbox == true
  end
  return value
end

function methods.EnableMouse(_, _, st, enable)
  st.mouseClick = enable and true or false
  st.mouseMotion = enable and true or false
end

function methods.SetMouseClickEnabled(_, _, st, enable)
  st.mouseClick = enable and true or false
end

function methods.SetMouseMotionEnabled(_, _, st, enable)
  st.mouseMotion = enable and true or false
end

methods.EnableMouseMotion = methods.SetMouseMotionEnabled

function methods.IsMouseClickEnabled(_, _, st)
  return mouseState(st, "mouseClick")
end

function methods.IsMouseMotionEnabled(_, _, st)
  return mouseState(st, "mouseMotion")
end

function methods.IsMouseEnabled(_, _, st)
  return mouseState(st, "mouseClick") or mouseState(st, "mouseMotion")
end

-- True when obj is the mouse focus or one of its ancestors.
function methods.IsMouseOver(w, obj)
  local frame = w.input.mouseFocus
  while frame do
    if frame == obj then
      return true
    end
    frame = w.ui.state[frame].parent
  end
  return false
end

function methods.IsMouseMotionFocus(w, obj)
  return w.input.mouseFocus == obj
end

-- source: wiki API_ScriptRegion_EnableMouse, "Setting the OnEnter/Leave, OnMouseDown/Up script automatically implies
-- `EnableMouse(true)`" (row I5). OnClick enables nothing; a rejected or cleared script
-- changes nothing.
function methods.SetScript(w, obj, st, script, fn)
  if fn ~= nil and MOUSE_SCRIPTS[script] and BehaviourScripts.methods.HasScript(w, obj, st, script) then
    st.mouseMotion = true
    st.mouseClick = true
  end
  return BehaviourScripts.methods.SetScript(w, obj, st, script, fn)
end

-- Button and CheckButton. State: st.disabled (nil = enabled), st.checked, st.clicks (set of "<Button>Up|Down";
-- nil = left button up only), st.clicking (true while a click's scripts run).
local ANY_BUTTONS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
local DEFAULT_CLICKS = { LeftButtonUp = true }

-- source: assumed (row I1) OnEnable/OnDisable fire only when the enabled state changes.
local function setEnabled(w, obj, st, enabled)
  local disabled = not enabled
  if (st.disabled or false) == disabled then
    return
  end
  st.disabled = disabled
  w:callScript(obj, enabled and "OnEnable" or "OnDisable")
end

local function enable(w, obj, st)
  setEnabled(w, obj, st, true)
end

local function disable(w, obj, st)
  setEnabled(w, obj, st, false)
end

local function isEnabled(_, _, st)
  return not st.disabled
end

local function addClicks(clicks, name)
  local direction = name:match("^Any(%a+)$")
  if not direction then
    clicks[name] = true
    return
  end
  for _, button in ipairs(ANY_BUTTONS) do
    clicks[button .. direction] = true
  end
end

-- source: confirmed (row I2) RegisterForClicks("AnyUp" | "<Button>Up|Down", ...) replaces the registered set.
local function registerForClicks(_, _, st, ...)
  local clicks = {}
  for i = 1, select("#", ...) do
    addClicks(clicks, (select(i, ...)))
  end
  st.clicks = clicks
end

function M.isRegistered(w, frame, button, direction)
  local clicks = w.ui.state[frame].clicks or DEFAULT_CLICKS
  return clicks[button .. direction] == true
end

local function fireClickScripts(w, frame, button, down)
  w:callScript(frame, "PreClick", button, down)
  w:callScript(frame, "OnClick", button, down)
  w:callScript(frame, "PostClick", button, down)
end

-- source: assumed (row I4) a CheckButton flips its checked state before PreClick. Addon errors in the scripts are
-- recorded, not raised; an intrinsic (kit) handler's error is raised after st.clicking returns to its value before
-- this click (a nested click keeps the outer one in progress).
function M.runClick(w, frame, button, down)
  local st = w.ui.state[frame]
  if st.plan.isA.checkbutton then
    st.checked = not st.checked
  end
  local wasClicking = st.clicking
  st.clicking = true
  local ok, err = pcall(fireClickScripts, w, frame, button, down)
  st.clicking = wasClicking
  if not ok then
    error(err, 0)
  end
end

-- source: confirmed (row I3) Click() ignores registration, passes isDown to the scripts (false when omitted), and
-- does nothing on a disabled button or one already being clicked; assumed (row I3, kit choice) it skips the mouse and
-- visibility checks and turns a non-boolean isDown into a boolean.
local function click(w, obj, st, button, isDown)
  if st.disabled or st.clicking then
    return
  end
  M.runClick(w, obj, button or "LeftButton", isDown and true or false)
end

local function setChecked(_, _, st, checked)
  st.checked = checked and true or false
end

local function getChecked(_, _, st)
  return st.checked == true
end

local buttonMethods = {
  Enable = enable,
  Disable = disable,
  IsEnabled = isEnabled,
  RegisterForClicks = registerForClicks,
  Click = click,
}
for name, impl in pairs(buttonMethods) do
  M.typed[name] = M.onlyFor("button", impl)
end
M.typed.SetEnabled = M.onlyFor("button", function(w, obj, st, enabled)
  setEnabled(w, obj, st, enabled and true or false)
end)
M.typed.SetChecked = M.onlyFor("checkbutton", setChecked)
M.typed.GetChecked = M.onlyFor("checkbutton", getChecked)

-- EditBox. Focus lives in w.input.editFocus (one box at a time); it is updated before the focus scripts run.
local function setFocus(w, obj)
  local old = w.input.editFocus
  if old == obj then
    return
  end
  w.input.editFocus = obj
  if old then
    w:callScript(old, "OnEditFocusLost")
  end
  w:callScript(obj, "OnEditFocusGained")
end

local function clearFocus(w, obj)
  if w.input.editFocus ~= obj then
    return
  end
  w.input.editFocus = nil
  w:callScript(obj, "OnEditFocusLost")
end

local function hasFocus(w, obj)
  return w.input.editFocus == obj
end

-- source: confirmed (row I6) SetText fires OnTextSet(self), then OnTextChanged(self, false) only when the text
-- changed, so a handler that sets its own text does not recurse; assumed (row I6) OnTextSet fires for unchanged text.
local function setEditText(w, obj, st, text)
  local old = st.text
  st.text = tostring(text or "")
  w:callScript(obj, "OnTextSet")
  if st.text ~= old then
    w:callScript(obj, "OnTextChanged", false)
  end
end

M.typed.SetFocus = M.onlyFor("editbox", setFocus)
M.typed.ClearFocus = M.onlyFor("editbox", clearFocus)
M.typed.HasFocus = M.onlyFor("editbox", hasFocus)
M.typed.SetText = M.onlyFor("editbox", setEditText)

return M
