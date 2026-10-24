-- Hand-written text, font and status bar semantics; methods are fn(w, obj, st, ...) like ui/behaviour.lua.
-- A FontString or Font without its own font or text color reads it through its font object chain.
local M = {}

local Layout = require("ui.layout")

local unpack = unpack

local methods = {}
M.methods = methods

local MAX_FONT_DEPTH = 10
local DEFAULT_ALPHA = 1
local WHITE = { 1, 1, 1, DEFAULT_ALPHA }
local COLOR_FIELDS = 4
local DEFAULT_VALUE = 0

local function resolveObject(value)
  if type(value) == "string" then
    return _G[value]
  end
  return value
end

-- st[field], else the first one set along the font object chain.
local function inherited(w, st, field)
  for _ = 1, MAX_FONT_DEPTH do
    if not st then
      return nil
    end
    if st[field] ~= nil then
      return st[field]
    end
    st = st.fontObject and w.ui.state[st.fontObject]
  end
  return nil
end

local function color(r, g, b, a)
  return { r, g, b, a or DEFAULT_ALPHA }
end

function methods.SetText(_, _, st, text)
  st.text = text ~= nil and tostring(text) or nil
end

function methods.SetFormattedText(_, _, st, format, ...)
  st.text = string.format(format, ...)
end

function methods.GetText(_, _, st)
  return st.text
end

function methods.SetFont(_, _, st, path, size, flags)
  st.font = { path, size, flags }
end

function methods.GetFont(w, _, st)
  local font = inherited(w, st, "font")
  if font then
    return font[1], font[2], font[3]
  end
end

function methods.SetFontObject(_, _, st, font)
  st.fontObject = resolveObject(font)
end

function methods.GetFontObject(_, _, st)
  return st.fontObject
end

-- Copies the source's effective font, text color and generic settings (shadow, justify, ...).
function methods.CopyFontObject(w, _, st, source)
  local sourceState = w.ui.state[resolveObject(source)]
  if not sourceState then
    return
  end
  st.font = inherited(w, sourceState, "font")
  st.textColor = inherited(w, sourceState, "textColor")
  for key, value in pairs(sourceState.values) do
    st.values[key] = value
  end
end

function methods.SetTextColor(_, _, st, r, g, b, a)
  st.textColor = color(r, g, b, a)
end

function methods.GetTextColor(w, _, st)
  return unpack(inherited(w, st, "textColor") or WHITE, 1, COLOR_FIELDS)
end

-- Through Layout.autoSize (ui/measure.lua underneath): the font chain, size 12 when none, and wrapped at the
-- width the anchors or SetWidth fix.
function methods.GetStringWidth(w, obj)
  return Layout.autoSize(w, obj, "x")
end

function methods.GetStringHeight(w, obj)
  return Layout.autoSize(w, obj, "y", Layout.wrapWidth(w, obj))
end

-- Status bars and sliders -------------------------------------------------------------------------------------

function methods.SetStatusBarColor(_, _, st, r, g, b, a)
  st.barColor = color(r, g, b, a)
end

function methods.GetStatusBarColor(_, _, st)
  return unpack(st.barColor or WHITE, 1, COLOR_FIELDS)
end

-- The value clamps to the range once one is set.
local function clamp(st, value)
  local range = st.range
  if not range or type(value) ~= "number" then
    return value
  end
  return math.max(range[1], math.min(range[2], value))
end

-- Stores the clamped value; a change fires OnValueChanged(self, value, userInput = false) like the client.
local function changeValue(w, obj, st, value)
  value = clamp(st, value)
  if value == (st.value or DEFAULT_VALUE) then
    return
  end
  st.value = value
  w:callScript(obj, "OnValueChanged", value, false)
end

function methods.SetMinMaxValues(w, obj, st, minValue, maxValue)
  st.range = { minValue, maxValue }
  changeValue(w, obj, st, st.value or DEFAULT_VALUE)
end

function methods.GetMinMaxValues(_, _, st)
  local range = st.range
  if range then
    return range[1], range[2]
  end
  return 0, 0
end

methods.SetValue = changeValue

function methods.GetValue(_, _, st)
  return st.value or DEFAULT_VALUE
end

return M
