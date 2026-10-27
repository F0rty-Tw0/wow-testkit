-- Hand-written Slider and StatusBar behaviour beyond the value and range (ui/behaviour_text.lua): orientation, the slider
-- value step, the status bar fill options, and the thumb and bar texture regions. State lives in st.rangeOpts (st.range
-- is the minimum and maximum); a widget nothing was set on has none and reads the defaults. A thumb or bar texture
-- region has st.widgetPart, so the draw order skips it and the widget exports its look (render_widgets_range.lua).
-- Registers through Typed.add, so M.methods stays empty. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local BehaviourText = require("ui.behaviour_text")
local Slot = require("ui.role_slot")
local Typed = require("ui.typed")

M.methods = {}

-- source: V12 (confirmed): wiki API:Slider_SetOrientation default=VERTICAL and API:StatusBar_SetOrientation
-- default=HORIZONTAL, XML/Slider orientation default VERTICAL, XML/StatusBar default HORIZONTAL.
M.DEFAULT_ORIENTATION = { slider = "VERTICAL", statusbar = "HORIZONTAL" }

-- source: W44 (confirmed): xsd:203-210 lists Standard, StandardNoRangeFill, Center, Reverse; the values are
-- Enum.StatusBarFillStyle 0 to 3 (simplestatusbarconstantsdocumentation.lua).
local FILL_STYLES = { [0] = "STANDARD", "STANDARDNORANGEFILL", "CENTER", "REVERSE" }
M.DEFAULT_FILL_STYLE = "STANDARD"

local NO_OPTIONS = {}
local ARTWORK = "ARTWORK"

-- The options set so far; an empty table for a widget nothing was set on. Treat the result as read-only.
function M.read(st)
  return st.rangeOpts or NO_OPTIONS
end

local function write(st)
  st.rangeOpts = st.rangeOpts or {}

  return st.rangeOpts
end

-- The orientation of a slider or status bar (kind "slider" or "statusbar") for the render snapshot.
function M.orientation(st, kind)
  return M.read(st).orientation or M.DEFAULT_ORIENTATION[kind]
end

local function toBoolean(value)
  return value and true or false
end

local function toFillStyle(value)
  return FILL_STYLES[value] or value
end

local function identity(value)
  return value
end

-- Set<name> stores key; Get<name> answers it, or default for a widget that never set it, on the types isA.
local function option(isA, name, key, default, convert)
  convert = convert or identity
  Typed.add("Set" .. name, isA, function(_, _, st, value)
    write(st)[key] = convert(value)
  end)
  Typed.add("Get" .. name, isA, function(_, _, st)
    local value = M.read(st)[key]
    if value == nil then
      return default
    end

    return value
  end)
end

-- source: W42 (confirmed meaning): obeyStepOnDrag and stepsPerPage are stored; a step of 0 is the xsd's unset value.
option("slider", "Orientation", "orientation", M.DEFAULT_ORIENTATION.slider)
option("slider", "ValueStep", "step", 0)
option("slider", "ObeyStepOnDrag", "obey", false, toBoolean)
option("slider", "StepsPerPage", "pages", 0)

-- source: W44 (confirmed): xsd:1004-1007 orientation HORIZONTAL, rotatesTexture false, reverseFill false, fillStyle Standard.
option("statusbar", "Orientation", "orientation", M.DEFAULT_ORIENTATION.statusbar)
option("statusbar", "ReverseFill", "reverse", false, toBoolean)
option("statusbar", "RotatesTexture", "rotates", false, toBoolean)
option("statusbar", "FillStyle", "fillStyle", M.DEFAULT_FILL_STYLE, toFillStyle)

-- source: assumed (W42) a slider that obeys its step snaps SetValue to min + floor((v - min) / step + 0.5) * step; the
-- value then clamps and fires OnValueChanged as before. A step of 0 is continuous.
local function snapped(st, value)
  local opts = M.read(st)
  local step = opts.step
  if not (opts.obey and step and step > 0 and type(value) == "number") then
    return value
  end
  local min = st.range and st.range[1] or 0

  return min + math.floor((value - min) / step + 0.5) * step
end

Typed.add("SetValue", "slider", function(w, obj, st, value)
  BehaviourText.methods.SetValue(w, obj, st, snapped(st, value))
end)

-- Thumb and bar texture --------------------------------------------------------------------------------------

local KEYS = { mark = "widgetPart", owned = "partOwned" }

-- source: assumed (W43, W44) a texture object becomes the thumb or bar and is re-parented to the widget; a path or file
-- id retextures the region already there (adopted or made by the widget), else fills a region the widget makes.
local function setPart(part)
  return function(w, obj, st, asset)
    local opts = write(st)
    local old = opts[part]
    if Slot.isTexture(w, asset) then
      if old ~= asset then
        Slot.release(w, opts, part, KEYS)
        asset:SetParent(obj)
        Slot.claim(w, opts, part, asset, false, KEYS)
      end

      return
    end
    if not old then
      Slot.claim(w, opts, part, obj:CreateTexture(nil, ARTWORK), true, KEYS)
    end
    opts[part]:SetTexture(asset)
  end
end

local function getPart(part)
  return function(_, _, st)
    return M.read(st)[part]
  end
end

Typed.add("SetThumbTexture", "slider", setPart("thumb"))
Typed.add("GetThumbTexture", "slider", getPart("thumb"))
Typed.add("SetStatusBarTexture", "statusbar", setPart("bar"))
Typed.add("GetStatusBarTexture", "statusbar", getPart("bar"))

return M
