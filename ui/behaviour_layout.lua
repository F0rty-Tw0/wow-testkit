-- Anchors and sizes: SetPoint and its queries, SetAllPoints, and the size setters and getters.
-- Each method is fn(w, obj, st, ...) like ui/behaviour.lua's; an anchor is { point, relativeTo | nil, relativePoint,
-- offsetX, offsetY } in st.points, one per point name in set order, and relativeTo == nil means the screen.
local M = {}

local AddonEnv = require("addon_env")
local Callsite = require("ui.callsite")
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
-- assumed (LY4): a global that holds no region (a string, a number) anchors to the screen, as a missing one does.
local function relativeOf(w, st, relativeTo, explicit)
  if type(relativeTo) == "string" then
    local global = AddonEnv.global(w, relativeTo)
    return type(global) == "table" and global or nil
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
local function parsePoint(w, st, n, point, a, b, c, d)
  point = upper(point)
  if type(a) == "number" then
    return { point, relativeOf(w, st, nil), point, a, b or 0 }
  end
  local explicit = n >= 2
  if type(b) == "number" then
    return { point, relativeOf(w, st, a, explicit), point, b, c or 0 }
  end
  return { point, relativeOf(w, st, a, explicit), upper(b) or point, c or 0, d or 0 }
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

-- source: confirmed Blizzard_SharedXML/UI.xsd:4-16 FRAMEPOINT, the point names; any case is taken (retail
-- blizzard_gluexml/mainline/characterservices.lua:501 SetPoint("Left", ...)).
M.FRAMEPOINT = {}
for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER" }) do
  M.FRAMEPOINT[point] = true
end

-- source: assumed (LY15, no Lua shows the C side) a point or relativePoint name outside FRAMEPOINT raises at the caller and
-- adds no anchor. A non-string is left as before.
local function checkPoints(anchor)
  for _, point in ipairs({ anchor[1], anchor[3] }) do
    if type(point) == "string" and not M.FRAMEPOINT[point] then
      error(string.format("SetPoint: '%s' is not a FRAMEPOINT", point), Callsite.level())
    end
  end
end

function methods.SetPoint(w, obj, st, ...)
  local anchor = parsePoint(w, st, select("#", ...), ...)
  checkPoints(anchor)
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
  local target = relativeOf(w, st, relativeTo)
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

-- source: row LY13 (`ignoreRect`, default false), row LY5/LY6: with ignoreRect only the size the addon set counts;
-- otherwise a valid rect's size, else the set size, else a FontString's text size (row LY10), else 0.
local function sizeOf(w, obj, st, axis, ignoreRect)
  local rect = not ignoreRect and Layout.rect(w, obj)
  if rect then
    return rect[axis == "x" and "width" or "height"]
  end
  local set
  if axis == "x" then
    set = st.width
  else
    set = st.height
  end
  if set then
    return set
  end
  return not ignoreRect and Layout.autoSize(w, obj, axis, Layout.wrapWidth(w, obj)) or 0
end

function methods.GetWidth(w, obj, st, ignoreRect)
  return sizeOf(w, obj, st, "x", ignoreRect)
end

function methods.GetHeight(w, obj, st, ignoreRect)
  return sizeOf(w, obj, st, "y", ignoreRect)
end

function methods.GetSize(w, obj, st, ignoreRect)
  return sizeOf(w, obj, st, "x", ignoreRect), sizeOf(w, obj, st, "y", ignoreRect)
end

-- Rect ---------------------------------------------------------------------------------------------------------

-- source: row LY6: a region with no resolvable rect returns nothing (not nil) from these getters.
function methods.GetLeft(w, obj)
  local rect = Layout.rect(w, obj)
  if rect then
    return rect.left
  end
end

function methods.GetRight(w, obj)
  local rect = Layout.rect(w, obj)
  if rect then
    return rect.left + rect.width
  end
end

function methods.GetBottom(w, obj)
  local rect = Layout.rect(w, obj)
  if rect then
    return rect.bottom
  end
end

function methods.GetTop(w, obj)
  local rect = Layout.rect(w, obj)
  if rect then
    return rect.bottom + rect.height
  end
end

function methods.GetCenter(w, obj)
  local rect = Layout.rect(w, obj)
  if rect then
    return rect.left + rect.width / 2, rect.bottom + rect.height / 2
  end
end

function methods.GetRect(w, obj)
  local rect = Layout.rect(w, obj)
  if rect then
    return rect.left, rect.bottom, rect.width, rect.height
  end
end

-- source: row LY7: GetScaledRect is GetRect times the effective scale, i.e. the pixel rect.
function methods.GetScaledRect(w, obj)
  local pixel = Layout.pixelRect(w, obj)
  if pixel then
    return pixel.left, pixel.bottom, pixel.right - pixel.left, pixel.top - pixel.bottom
  end
end

-- assumed (row LY6): a region is valid exactly when its rect resolves.
function methods.IsRectValid(w, obj)
  return Layout.rect(w, obj) ~= nil
end

return M
