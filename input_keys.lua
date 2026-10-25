-- Keyboard input: what a key press does. An EditBox with focus takes the key alone; otherwise the visible, keyboard-enabled
-- frames get it topmost first until one stops propagating; if none did, the key's binding runs. Every rule is assumed
-- (the client's own Lua and docs do not settle it); the tests carry the matching `_assumed` names.
local M = {}

local Bindings = require("bindings")
local Input = require("input")
local LayoutHit = require("ui.layout_hit")

-- Held modifiers in the order the combination string names them.
local MODIFIERS = { { "alt", "ALT" }, { "ctrl", "CTRL" }, { "shift", "SHIFT" } }
local BACKSPACE = "BACKSPACE"
-- The last UTF-8 character: a lead byte and its continuation bytes at the end of the text.
local LAST_CHAR = "[^\128-\191][\128-\191]*$"

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

-- source: assumed (K1) BACKSPACE removes the last UTF-8 character and fires OnTextChanged(true).
local function backspace(w, box)
  local st = w.ui.state[box]
  local text = st.text or ""
  if text == "" then
    return
  end
  st.text = text:gsub(LAST_CHAR, "")
  w:callScript(box, "OnTextChanged", true)
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

-- A key press, down then up. key is the client's key name ("A", "1", "ENTER", "F1"); mods = { shift?, ctrl?, alt? }.
-- Returns { consumedBy? = the EditBox or the frame that stopped it, binding? = the command that ran }.
-- source: assumed (K1) only a visible focused EditBox takes the key.
function M.press(w, key, mods)
  key = key:upper()
  local box = w.input.editFocus
  if box and box:IsVisible() then
    editKey(w, box, key)

    return { consumedBy = box }
  end
  local reached, stopper = keyDown(w, keyboardFrames(w), key)
  -- source: assumed (K3) the key's binding runs when no frame stopped it: down on key down, runOnUp on key up.
  local command = not stopper and w.bindings and Bindings.lookup(w, combination(key, mods))
  if command then
    Bindings.run(w, command, "down")
  end
  for _, frame in ipairs(reached) do
    w:callScript(frame, "OnKeyUp", key)
  end
  if command then
    Bindings.run(w, command, "up")
  end

  return { consumedBy = stopper, binding = command or nil }
end

return M
