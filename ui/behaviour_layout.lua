-- Anchors and sizes: SetPoint and its queries, SetAllPoints, and the size setters and getters.
-- Each method is fn(w, obj, st, ...) like ui/behaviour.lua's; an anchor is { point, relativeTo | nil, relativePoint,
-- offsetX, offsetY } in st.points, one per point name in set order, and relativeTo == nil means the screen.
local M = {}

local Layout = require("ui.layout")

local unpack = unpack

local methods = {}
M.methods = methods

local ANCHOR_FIELDS = 5

local function upper(point)
  return type(point) == "string" and point:upper() or point
end

-- A frame name resolves through _G. Omitted (not explicit) means the parent; with no parent, or an explicit nil,
-- the screen.
-- source: wiki API_Region_SetPoint, relativeTo: "If omitted, anchors to the parent region if applicable, otherwise
-- to the screen dimensions." and "If explicitly passed `nil`, anchors relative to the screen dimensions."
-- source: wiki API_Region_SetPoint, relativeTo is `ScriptRegion,string?`: "For example `UIParent` or `"UIParent"`."
local function relativeOf(st, relativeTo, explicit)
  if type(relativeTo) == "string" then
    return _G[relativeTo]
  end
  if relativeTo ~= nil then
    return relativeTo
  end
  if explicit then
    return nil
  end
  return st.parent
end

-- The client's SetPoint forms: (point), (point, x, y), (point, relativeTo, x, y),
-- (point, relativeTo, relativePoint [, x, y]). Missing offsets are 0; a missing relativePoint is point.
-- n is the argument count including point; n >= 2 with a nil `a` is an explicit nil relativeTo.
local function parsePoint(st, n, point, a, b, c, d)
  point = upper(point)
  if type(a) == "number" then
    return { point, relativeOf(st, nil), point, a, b or 0 }
  end
  local explicit = n >= 2
  if type(b) == "number" then
    return { point, relativeOf(st, a, explicit), point, b, c or 0 }
  end
  return { point, relativeOf(st, a, explicit), upper(b) or point, c or 0, d or 0 }
end

local function addAnchor(st, anchor)
  for i, existing in ipairs(st.points) do
    if existing[1] == anchor[1] then
      st.points[i] = anchor
      return
    end
  end
  st.points[#st.points + 1] = anchor
end

function methods.SetPoint(w, obj, st, ...)
  local anchor = parsePoint(st, select("#", ...), ...)
  Layout.checkAnchor(w, obj, anchor)
  addAnchor(st, anchor)
end

function methods.ClearAllPoints(_, _, st)
  st.points = {}
end

function methods.ClearPoint(_, _, st, point)
  point = upper(point)
  for i, anchor in ipairs(st.points) do
    if anchor[1] == point then
      table.remove(st.points, i)
      return
    end
  end
end

function methods.GetPoint(_, _, st, index)
  local anchor = st.points[index or 1]
  if anchor then
    return unpack(anchor, 1, ANCHOR_FIELDS)
  end
end

function methods.GetPointByName(_, _, st, point)
  point = upper(point)
  for _, anchor in ipairs(st.points) do
    if anchor[1] == point then
      return unpack(anchor, 1, ANCHOR_FIELDS)
    end
  end
end

function methods.GetNumPoints(_, _, st)
  return #st.points
end

function methods.SetAllPoints(w, obj, st, relativeTo)
  local target = relativeOf(st, relativeTo)
  Layout.checkAnchor(w, obj, { "TOPLEFT", target })
  st.points = {
    { "TOPLEFT", target, "TOPLEFT", 0, 0 },
    { "BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0 },
  }
end

-- Size --------------------------------------------------------------------------------------------------------

function methods.SetSize(_, _, st, width, height)
  st.width, st.height = width, height
end

function methods.SetWidth(_, _, st, width)
  st.width = width
end

function methods.SetHeight(_, _, st, height)
  st.height = height
end

function methods.GetWidth(_, _, st)
  return st.width or 0
end

function methods.GetHeight(_, _, st)
  return st.height or 0
end

function methods.GetSize(_, _, st)
  return st.width or 0, st.height or 0
end

return M
