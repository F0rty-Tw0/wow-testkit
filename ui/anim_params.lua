-- Animation property getters and the setters that do not store their arguments as given. The generic setters keep
-- SetDuration, SetStartDelay, SetEndDelay, SetOrder, SetSmoothing, SetFromAlpha, SetToAlpha, SetOffset, SetScaleFrom,
-- SetScaleTo, SetOrigin and SetTarget in st.values; the getters here answer the stored value or the default through
-- Anim.values, the same read the playback uses. Registers through Typed.add for "animation", so M.methods stays empty.
-- Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Anim = require("ui.anim")
local Typed = require("ui.typed")

local select = select
local unpack = unpack

M.methods = {}

-- Getter -> setter key it reads.
local GETTERS = {
  GetDuration = "Duration",
  GetStartDelay = "StartDelay",
  GetEndDelay = "EndDelay",
  GetOrder = "Order",
  GetSmoothing = "Smoothing",
  GetFromAlpha = "FromAlpha",
  GetToAlpha = "ToAlpha",
  GetOffset = "Offset",
  GetScaleFrom = "ScaleFrom",
  GetScaleTo = "ScaleTo",
  GetOrigin = "Origin",
}

local function getter(key)
  return function(_, _, st)
    return unpack(Anim.values(st, key))
  end
end

for name, key in pairs(GETTERS) do
  Typed.add(name, "animation", getter(key))
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- Scale:SetScale(x, y) sets the factor the scale ends at. source: assumed (no row): scaleX and scaleY of the XML Scale
-- element are scaleTo, the start factor staying 1.
Typed.add("SetScale", "scale", function(_, _, st, ...)
  st.values.ScaleTo = pack(...)
end)
Typed.add("GetScale", "scale", getter("ScaleTo"))

-- Degrees and radians are one angle, kept in radians.
Typed.add("SetDegrees", "rotation", function(_, _, st, degrees)
  st.values.Radians = pack(math.rad(degrees))
end)
Typed.add("SetRadians", "rotation", function(_, _, st, radians)
  st.values.Radians = pack(radians)
end)
Typed.add("GetRadians", "rotation", getter("Radians"))
Typed.add("GetDegrees", "rotation", function(_, _, st)
  return math.deg(Anim.value(st, "Radians"))
end)

Typed.add("GetTarget", "animation", function(w, animation)
  return Anim.target(w, animation)
end)

-- The group's progress of this animation: Anim.progress is linear, the smooth one goes through the curve.
local function progressOf(w, animation, st)
  local group = st.parent

  return group and Anim.progress(w, group, w.now)[animation] or 0
end

Typed.add("GetProgress", "animation", function(w, animation, st)
  return progressOf(w, animation, st)
end)
Typed.add("GetSmoothProgress", "animation", function(w, animation, st)
  return Anim.smooth(Anim.value(st, "Smoothing"), progressOf(w, animation, st))
end)
-- kit choice (no row): the seconds into the animation itself, delays excluded.
Typed.add("GetElapsed", "animation", function(w, animation, st)
  return progressOf(w, animation, st) * Anim.value(st, "Duration")
end)

return M
