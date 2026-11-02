-- Keyboard input: what a key does. An EditBox with focus takes the key alone; otherwise the visible, keyboard-enabled
-- frames get it topmost first until one stops propagating; if none did, the key's binding runs. A key goes down and later
-- up: the frames reached and the command resolved on the way down are remembered in w.input.heldKeys[KEY], and the way
-- up finishes exactly those, whatever the modifiers are by then. Every rule is assumed (the client's own Lua and docs do
-- not settle it) except where a line says confirmed; the tests carry the matching `_assumed` names.
local M = {}

local Bindings = require("bindings")
local BehaviourEdit = require("ui.behaviour_edit")
local Input = require("input")
local LayoutHit = require("ui.layout_hit")

-- Held modifiers in the order the combination string names them.
local MODIFIERS = { { "alt", "ALT" }, { "ctrl", "CTRL" }, { "shift", "SHIFT" } }
local BACKSPACE = "BACKSPACE"

-- "ALT-CTRL-SHIFT-<KEY>" with only the held modifiers.
local function combination(key, mods)
  local parts = {}
  for _, modifier in ipairs(MODIFIERS) do
    if mods and mods[modifier[1]] then
      parts[#parts + 1] = modifier[2]
    end
  end
  parts[#parts + 1] = key

  return table.concat(parts, "-")
end

-- source: assumed (K1) BACKSPACE removes the selection, else the UTF-8 character before the cursor, and fires
-- OnTextChanged(true) when it removed something.
local function backspace(w, box)
  if BehaviourEdit.backspace(w.ui.state[box]) then
    w:callScript(box, "OnTextChanged", true)
  end
end

-- source: assumed (K1) an EditBox with focus gets the key and nothing else does: OnKeyDown(key), then ENTER, ESCAPE and
-- TAB run Input.press or BACKSPACE edits the text, then OnKeyUp(key).
local function editKey(w, box, key)
  w:callScript(box, "OnKeyDown", key)
  if key == BACKSPACE then
    backspace(w, box)
  elseif Input.KEY_SCRIPTS[key] then
    Input.press(w, box, key)
  end
  w:callScript(box, "OnKeyUp", key)
end

-- The visible frames with keyboard input enabled, topmost first.
local function keyboardFrames(w)
  local frames = {}
  for frame, st in pairs(w.ui.state) do
    if st.plan.isFrame and st.keyboard and frame:IsVisible() then
      frames[#frames + 1] = frame
    end
  end
  table.sort(frames, function(a, b)
    return LayoutHit.above(w, a, b)
  end)

  return frames
end

-- Read from the stored value: the getter would count an unset flag as unscripted.
local function propagates(w, frame)
  local value = w.ui.state[frame].values.PropagateKeyboardInput

  return value ~= nil and value[1] == true
end

-- source: assumed (K2) OnKeyDown(frame, key) on each frame topmost first; the walk stops at the first frame whose
-- GetPropagateKeyboardInput() is false after its handler ran. Returns the frames reached and the one that stopped it.
local function keyDown(w, frames, key)
  local reached = {}
  for _, frame in ipairs(frames) do
    reached[#reached + 1] = frame
    w:callScript(frame, "OnKeyDown", key)
    if not propagates(w, frame) then
      return reached, frame
    end
  end

  return reached, nil
end

-- Puts the held modifiers back, then returns fn's results or raises its error.
local function restoring(w, held, ok, ...)
  w.mock.modifiers = held
  if not ok then
    error((...), 0)
  end

  return ...
end

-- Runs fn(...) with exactly the modifiers in mods held (shift, ctrl, alt; nil holds none) and puts the previous ones back
-- afterwards, also when fn raises. Returns fn's results.
-- source: assumed (K3) the modifiers a key names are the ones held while it runs: IsShiftKeyDown and the others read them
-- in OnKeyDown, OnKeyUp and the binding.
function M.holding(w, mods, fn, ...)
  local held = w.mock.modifiers
  mods = mods or {}
  w.mock.modifiers = { shift = mods.shift == true, ctrl = mods.ctrl == true, alt = mods.alt == true }

  return restoring(w, held, pcall(fn, ...))
end

-- A key goes down. key is the client's key name ("A", "1", "ENTER", "F1"); mods = { shift?, ctrl?, alt? }. Returns
-- { consumedBy? = the EditBox or the frame that stopped it, binding? = the command that ran on down, ignored? = true
-- when the key is already held, which runs nothing }.
-- source: assumed (K1) only a visible focused EditBox takes the key, and it gets the whole OnKeyDown..OnKeyUp at once:
-- nothing is held.
function M.down(w, key, mods)
  key = key:upper()
  local box = w.input.editFocus
  local typing = box and box:IsVisible()
  if typing then
    editKey(w, box, key)

    return { consumedBy = box }
  end
  if w.input.heldKeys[key] then
    return { ignored = true }
  end
  local reached, stopper = keyDown(w, keyboardFrames(w), key)
  -- source: assumed (K3) the key's binding runs when no frame stopped it, on key down with keystate "down".
  local command = not stopper and w.bindings and Bindings.lookup(w, combination(key, mods))
  command = command or nil
  w.input.heldKeys[key] = { reached = reached, stopper = stopper, command = command }
  if command then
    Bindings.run(w, command, "down")
  end

  return { consumedBy = stopper, binding = command }
end

-- A key comes up: OnKeyUp on the frames its down reached, then the up half of the command its down resolved (Bindings.run
-- runs it only when it is runOnUp). A key that is not held does nothing. Returns { consumedBy?, binding? } like down.
function M.up(w, key)
  key = key:upper()
  local held = w.input.heldKeys[key]
  if not held then
    return {}
  end
  w.input.heldKeys[key] = nil
  for _, frame in ipairs(held.reached) do
    w:callScript(frame, "OnKeyUp", key)
  end
  if held.command then
    Bindings.run(w, held.command, "up")
  end

  return { consumedBy = held.stopper, binding = held.command }
end

-- Forgets every held key without running its up half, for a world the sim resets: the next down of any key runs again.
function M.forgetHeld(w)
  w.input.heldKeys = {}
end

-- A key press, down then up; returns down's reply.
function M.press(w, key, mods)
  local reply = M.down(w, key, mods)
  M.up(w, key)

  return reply
end

return M
