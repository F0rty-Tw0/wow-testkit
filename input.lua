-- Input actions: what a click, hover or keystroke does to a frame's scripts, and why the client would ignore one.
-- Widget state lives in ui/behaviour_input.lua; the mouse and edit focus live in w.input.
local M = {}

local BehaviourEdit = require("ui.behaviour_edit")
local BehaviourInput = require("ui.behaviour_input")
local Layout = require("ui.layout")
local LayoutHit = require("ui.layout_hit")

local DEFAULT_BUTTON = "LeftButton"
local KEY_SCRIPTS = { ENTER = "OnEnterPressed", ESCAPE = "OnEscapePressed", TAB = "OnTabPressed" }
M.KEY_SCRIPTS = KEY_SCRIPTS
local NEWLINE = "\n"

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
-- [click handlers when registered Up]. A frame that is not a Button gets only the mouse scripts. beforeUp, when given,
-- runs while the button is held (a drag moves the cursor there).
local function runClick(w, frame, button, beforeUp)
  local isButton = isA(w, frame, "button")
  w:callScript(frame, "OnMouseDown", button)
  if isButton and BehaviourInput.isRegistered(w, frame, button, "Down") then
    BehaviourInput.runClick(w, frame, button, true)
  end
  if beforeUp then
    beforeUp()
  end
  w:callScript(frame, "OnMouseUp", button, true)
  if isButton and BehaviourInput.isRegistered(w, frame, button, "Up") then
    BehaviourInput.runClick(w, frame, button, false)
  end
end

-- source: assumed (row G7) GetMouseButtonClicked answers the clicked button while the click runs and what it answered
-- before once the click ends, even when it fails. A world without w.mock has no such answer.
function M.click(w, frame, button, beforeUp)
  button = button or DEFAULT_BUTTON
  local mock = w.mock
  local previous = mock and mock.clicked
  if mock then
    mock.clicked = button
  end
  local ok, err = pcall(runClick, w, frame, button, beforeUp)
  if mock then
    mock.clicked = previous
  end
  if not ok then
    error(err, 0)
  end
end

-- source: assumed (row I11) the focus is cleared before OnLeave runs.
function M.leave(w, frame)
  if w.input.mouseFocus ~= frame then
    error("leave: " .. label(w, frame) .. " does not have the mouse", 2)
  end
  w.input.mouseFocus = nil
  Layout.invalidate(w, frame)
  w:callScript(frame, "OnLeave", true)
end

-- source: assumed (row I11) the focus is set before OnEnter runs.
function M.enter(w, frame)
  local old = w.input.mouseFocus
  if old and old ~= frame then
    M.leave(w, old)
  end
  w.input.mouseFocus = frame
  Layout.invalidate(w, frame)
  w:callScript(frame, "OnEnter", true)
end

-- source: confirmed (row I8) each character: OnChar(char) then OnTextChanged(true); typed text bypasses SetText.
-- source: assumed (W35) a character the box refuses (max letters, a non-digit in a numeric box) fires neither script.
-- Returns whether the character went in.
function M.typeChar(w, box, char)
  if not BehaviourEdit.typeChar(w.ui.state[box], char) then
    return false
  end
  w:callScript(box, "OnChar", char)
  w:callScript(box, "OnTextChanged", true)

  return true
end

function M.type(w, box, text)
  box:SetFocus()
  for char in text:gmatch(BehaviourEdit.UTF8_CHAR) do
    M.typeChar(w, box, char)
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
  -- source: assumed (W38) in a multi-line box Enter types a newline and OnEnterPressed does not fire.
  if key == "ENTER" and BehaviourEdit.read(w.ui.state[box]).multiLine then
    M.typeChar(w, box, NEWLINE)
    return
  end
  w:callScript(box, script)
end

-- Hit testing ------------------------------------------------------------------------------------------------

-- The topmost visible, mouse-enabled frame whose hit rect holds the physical pixel x, y (origin top-left), or nil.
function M.frameAt(w, x, y)
  local best
  for frame, st in pairs(w.ui.state) do
    if
      st.plan.isFrame
      and frame:IsVisible()
      and frame:IsMouseEnabled()
      and LayoutHit.contains(w, frame, x, y)
      and (not best or LayoutHit.above(w, frame, best))
    then
      best = frame
    end
  end
  return best
end

-- Puts the cursor at the physical pixel x, y (origin top-left) for IsMouseOver; x == nil clears it.
function M.setCursor(w, x, y)
  w.input.cursor = x ~= nil and { x, y } or nil
end

-- source: confirmed (row I9) GetMouseFoci() returns the focus in a table, or an empty table.
function M.install(w)
  w:install("GetMouseFoci", function()
    local focus = w.input.mouseFocus
    return focus and { focus } or {}
  end, { gate = "api" })
end

return M
