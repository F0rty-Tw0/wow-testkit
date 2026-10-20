-- Input actions: what a click, hover or keystroke does to a frame's scripts, and why the client would ignore one.
-- Widget state lives in ui/behaviour_input.lua; the mouse and edit focus live in w.input.
local M = {}

local BehaviourInput = require("ui.behaviour_input")

local DEFAULT_BUTTON = "LeftButton"
local KEY_SCRIPTS = { ENTER = "OnEnterPressed", ESCAPE = "OnEscapePressed", TAB = "OnTabPressed" }
-- One UTF-8 character: a lead byte (%z is NUL in Lua 5.1 patterns) plus its continuation bytes.
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

-- Frame ------------------------------------------------------------------------------------------------------

-- True when value is a kit widget whose type is a Frame.
function M.isFrame(w, value)
  local st = type(value) == "table" and w.ui.state[value]
  return st and st.plan.isFrame == true or false
end

-- The frame's name, else "<ObjectType> in <parent label>" (just the type for a parentless frame).
local function label(w, frame)
  local st = w.ui.state[frame]
  if st.name then
    return st.name
  end
  if st.parent and w.ui.state[st.parent] then
    return st.plan.type .. " in " .. label(w, st.parent)
  end
  return st.plan.type
end

-- Blocked reasons -------------------------------------------------------------------------------------------

local function hiddenReason(w, frame)
  local current = frame
  while current and w.ui.state[current] do
    local st = w.ui.state[current]
    if not st.shown then
      return "hidden: " .. label(w, current) .. " is not shown"
    end
    current = st.parent
  end
  return nil
end

local function isA(w, frame, typeName)
  return w.ui.state[frame].plan.isA[typeName] == true
end

local function clickReason(w, frame, button)
  local st = w.ui.state[frame]
  if not BehaviourInput.methods.IsMouseClickEnabled(w, frame, st) then
    return "mouse disabled"
  end
  if not isA(w, frame, "button") then
    return nil
  end
  if st.disabled then
    return "disabled"
  end
  if BehaviourInput.isRegistered(w, frame, button, "Up") or BehaviourInput.isRegistered(w, frame, button, "Down") then
    return nil
  end
  return "not registered for " .. button
end

-- kind is "click", "enter" or "type"; returns the first reason the client would ignore the action, or nil.
function M.blockedReason(w, frame, kind, button)
  if not M.isFrame(w, frame) then
    return "not a frame"
  end
  local reason = hiddenReason(w, frame)
  if reason then
    return reason
  end
  if kind == "click" then
    return clickReason(w, frame, button or DEFAULT_BUTTON)
  end
  if kind == "enter" then
    local motion = BehaviourInput.methods.IsMouseMotionEnabled(w, frame, w.ui.state[frame])
    return not motion and "mouse disabled" or nil
  end
  return not isA(w, frame, "editbox") and "not an EditBox" or nil
end

-- Actions ---------------------------------------------------------------------------------------------------

-- source: confirmed (row I7) OnMouseDown(button), [click handlers when registered Down], OnMouseUp(button, true),
-- [click handlers when registered Up]. A frame that is not a Button gets only the mouse scripts.
function M.click(w, frame, button)
  button = button or DEFAULT_BUTTON
  local isButton = isA(w, frame, "button")
  w:callScript(frame, "OnMouseDown", button)
  if isButton and BehaviourInput.isRegistered(w, frame, button, "Down") then
    BehaviourInput.runClick(w, frame, button, true)
  end
  w:callScript(frame, "OnMouseUp", button, true)
  if isButton and BehaviourInput.isRegistered(w, frame, button, "Up") then
    BehaviourInput.runClick(w, frame, button, false)
  end
end

-- source: assumed (row I11) the focus is cleared before OnLeave runs.
function M.leave(w, frame)
  if w.input.mouseFocus ~= frame then
    error("leave: " .. label(w, frame) .. " does not have the mouse", 2)
  end
  w.input.mouseFocus = nil
  w:callScript(frame, "OnLeave", true)
end

-- source: assumed (row I11) the focus is set before OnEnter runs.
function M.enter(w, frame)
  local old = w.input.mouseFocus
  if old and old ~= frame then
    M.leave(w, old)
  end
  w.input.mouseFocus = frame
  w:callScript(frame, "OnEnter", true)
end

-- source: confirmed (row I8) each character: OnChar(char) then OnTextChanged(true); typed text bypasses SetText.
function M.type(w, box, text)
  box:SetFocus()
  local st = w.ui.state[box]
  for char in text:gmatch(UTF8_CHAR) do
    st.text = (st.text or "") .. char
    w:callScript(box, "OnChar", char)
    w:callScript(box, "OnTextChanged", true)
  end
end

function M.press(w, box, key)
  local script = KEY_SCRIPTS[key]
  if not script then
    error("press: unknown key '" .. tostring(key) .. "'", 2)
  end
  if w.input.editFocus ~= box then
    error("press: " .. label(w, box) .. " does not have focus", 2)
  end
  w:callScript(box, script)
end

-- source: confirmed (row I9) GetMouseFoci() returns the focus in a table, or an empty table.
function M.install(w)
  w:install("GetMouseFoci", function()
    local focus = w.input.mouseFocus
    return focus and { focus } or {}
  end, { gate = "api" })
end

return M
