-- Widget state and backdrop of a frame item in the render snapshot. Reads kit state or calls the *.methods bodies
-- directly, never the bound obj:Get*() methods, so no addon code runs and w.unscripted stays as it was.
local M = {}

local Assets = require("render_assets")
local BehaviourEdit = require("ui.behaviour_edit")
local BehaviourText = require("ui.behaviour_text")
local FontChain = require("ui.font_chain")
local Read = require("render_read")

-- source: row V12 (confirmed): a fresh Slider's orientation is VERTICAL (wiki API:Slider_SetOrientation default=VERTICAL,
-- XML/Slider orientation default VERTICAL) and a fresh StatusBar's is HORIZONTAL (wiki API:StatusBar_SetOrientation
-- default=HORIZONTAL, XML/StatusBar orientation default HORIZONTAL).
local DEFAULT_ORIENTATION = { slider = "VERTICAL", statusbar = "HORIZONTAL" }

local function orientation(st, typeKey)
  local pack = Read.stored(st, "Orientation")
  return pack and pack[1] or DEFAULT_ORIENTATION[typeKey]
end

local function copyLines(st)
  local lines = {}
  for i, message in ipairs(st.messages or {}) do
    lines[i] = { text = message.text, r = message.r, g = message.g, b = message.b }
  end
  return lines
end

local function messageFrame(_, _, st)
  return { type = "ScrollingMessageFrame", lines = copyLines(st) }
end

local function isZero(insets)
  return insets[1] == 0 and insets[2] == 0 and insets[3] == 0 and insets[4] == 0
end

-- The EditBox fields that appear only when set: selection, password, insets, and a justify other than LEFT. Reads the
-- justify from the font object chain (the setters store it), not through GetJustifyH, whose fresh default is CENTER.
local function editExtras(w, st, edit, widget)
  local selection, insets = edit.selection, edit.insets
  local justify = FontChain.value(w, st, "JustifyH")
  widget.selection = selection and { from = selection.from, to = selection.to } or nil
  widget.password = edit.password or nil
  widget.insets = not isZero(insets) and { l = insets[1], r = insets[2], t = insets[3], b = insets[4] } or nil
  widget.justifyH = justify and justify[1] ~= "LEFT" and justify[1] or nil
end

local function editBox(w, obj, st)
  local edit = BehaviourEdit.read(st)
  local widget = {
    type = "EditBox",
    text = BehaviourEdit.displayText(st),
    cursor = edit.cursor,
    focused = w.input.editFocus == obj,
    multiLine = edit.multiLine,
  }
  editExtras(w, st, edit, widget)

  return widget
end

local function checkButton(_, _, st)
  return { type = "CheckButton", checked = st.checked == true, enabled = not st.disabled }
end

-- state and locked appear only when they differ from the defaults, so a fresh Button exports as it always did.
local function button(_, _, st)
  local btn = st.btn or {}
  local state = btn.state ~= "NORMAL" and btn.state or nil

  return { type = "Button", enabled = not st.disabled, state = state, locked = btn.locked or nil }
end

local function slider(w, obj, st)
  local min, max = BehaviourText.methods.GetMinMaxValues(w, obj, st)
  return { type = "Slider", value = BehaviourText.methods.GetValue(w, obj, st), min = min, max = max, orientation = orientation(st, "slider") }
end

local function statusBar(w, obj, st)
  local min, max = BehaviourText.methods.GetMinMaxValues(w, obj, st)
  return {
    type = "StatusBar",
    value = BehaviourText.methods.GetValue(w, obj, st),
    min = min,
    max = max,
    color = Read.color({ BehaviourText.methods.GetStatusBarColor(w, obj, st) }),
    orientation = orientation(st, "statusbar"),
  }
end

-- First match wins, so a CheckButton (also a Button) reports as one.
local BUILDERS = {
  { isA = "scrollingmessageframe", build = messageFrame },
  { isA = "editbox", build = editBox },
  { isA = "checkbutton", build = checkButton },
  { isA = "button", build = button },
  { isA = "slider", build = slider },
  { isA = "statusbar", build = statusBar },
}

-- The widget table of a frame item, or nil for a plain frame.
function M.state(w, obj, st)
  for _, entry in ipairs(BUILDERS) do
    if st.plan.isA[entry.isA] then
      return entry.build(w, obj, st)
    end
  end
  return nil
end

local function copyInsets(insets)
  if type(insets) ~= "table" then
    return nil
  end
  return { left = insets.left, right = insets.right, top = insets.top, bottom = insets.bottom }
end

-- The backdrop of a frame item (st.backdrop = { info, color, borderColor }, framexml/fakes/backdrop.lua), or nil.
function M.backdrop(_, st, assets)
  local stored = st.backdrop
  if not stored then
    return nil
  end
  local info = stored.info
  return {
    bgFile = Assets.addFile(assets, info.bgFile),
    edgeFile = Assets.addFile(assets, info.edgeFile),
    tile = info.tile,
    tileSize = info.tileSize,
    edgeSize = info.edgeSize,
    insets = copyInsets(info.insets),
    color = Read.color(stored.color),
    borderColor = Read.color(stored.borderColor),
  }
end

return M
