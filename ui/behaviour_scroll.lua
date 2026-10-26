-- Hand-written ScrollFrame behaviour: the scroll child, the scroll offsets, the scroll ranges and their scripts. State
-- lives in st.scroll = { child, h, v, xrange, yrange } (xrange and yrange are the ranges OnScrollRangeChanged last
-- reported); a frame nothing was set on has none and reads M.DEFAULT. The child moves by the offsets through
-- ui/layout_shift.lua. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Layout = require("ui.layout")

local methods = {}
M.methods = methods

M.DEFAULT = { h = 0, v = 0, xrange = 0, yrange = 0 }

local NO_RANGE = 0

-- The scroll state set so far; M.DEFAULT (never written) for a frame nothing was set on. Treat the result as read-only.
function M.read(st)
  return st.scroll or M.DEFAULT
end

local function write(st)
  st.scroll = st.scroll or { h = 0, v = 0, xrange = 0, yrange = 0 }

  return st.scroll
end

-- source: assumed (W45) a range is max(0, child size - frame size) on the axis (size is "width" or "height"); a child or
-- frame without a rect has none.
local function rangeOf(w, obj, st, size)
  local child = M.read(st).child
  local childRect = child and Layout.rect(w, child)
  local rect = Layout.rect(w, obj)
  if not (childRect and rect) then
    return NO_RANGE
  end

  return math.max(NO_RANGE, childRect[size] - rect[size])
end

-- source: confirmed (W45) SetScrollChild sets the scroll child (wiki API_ScrollFrame_SetScrollChild); assumed (W45) it is
-- parented to the frame.
function methods.SetScrollChild(_, obj, st, child)
  write(st).child = child
  child:SetParent(obj)
end

function methods.GetScrollChild(_, _, st)
  return M.read(st).child
end

function methods.GetVerticalScrollRange(w, obj, st)
  return rangeOf(w, obj, st, "height")
end

function methods.GetHorizontalScrollRange(w, obj, st)
  return rangeOf(w, obj, st, "width")
end

function methods.GetVerticalScroll(_, _, st)
  return M.read(st).v
end

function methods.GetHorizontalScroll(_, _, st)
  return M.read(st).h
end

-- source: confirmed (W45) OnVerticalScroll(offset) and OnHorizontalScroll fire on a change; assumed (W45) the offset is not
-- clamped to the range.
local function setOffset(key, script)
  return function(w, obj, st, offset)
    local scroll = write(st)
    if scroll[key] == offset then
      return
    end
    scroll[key] = offset
    w:callScript(obj, script, offset)
  end
end

methods.SetVerticalScroll = setOffset("v", "OnVerticalScroll")
methods.SetHorizontalScroll = setOffset("h", "OnHorizontalScroll")

-- source: confirmed (W45) OnScrollRangeChanged(self, xrange, yrange) (securescrolltemplates.lua:64); assumed (W45) it fires
-- when UpdateScrollChildRect finds a range different from the one last reported.
function methods.UpdateScrollChildRect(w, obj, st)
  local scroll = write(st)
  local xrange, yrange = rangeOf(w, obj, st, "width"), rangeOf(w, obj, st, "height")
  if xrange == scroll.xrange and yrange == scroll.yrange then
    return
  end
  scroll.xrange, scroll.yrange = xrange, yrange
  w:callScript(obj, "OnScrollRangeChanged", xrange, yrange)
end

return M
