-- A region's size as its getters report it, and OnSizeChanged: a frame holding the script hears (width, height) when
-- that size differs from the last one it was told about (0, 0 at creation).
-- source: row LY16. Blizzard Lua shows two moments the client tells a frame. (1) Setters and anchor changes only mark
-- rects stale, and the change is told when the client next lays out: scrollutil.lua:337-340 ("This will invalidate the
-- ScrollBox and scroll target rects ... overwritten by doing a full update in the size changed handler"), and
-- lootframe.lua:181 / scrollingflatpanel.lua:35-49 fill a hidden ScrollBox, then resize its panel, and build the rows
-- only through ScrollBoxBaseMixin:OnSizeChanged (scrollbox.lua:119-129). (2) A measurement resolves the rect at once
-- and tells the frame from inside the call: scrollbox.lua:156-158 ("Multiple measurement APIs on the ScrollBox frame
-- can cause OnSizeChanged to be dispatched"), which is why FullUpdateInternal clears the script while it measures.
-- assumed (LY16): the kit's layout moment is one pass per sim step, after the OnUpdate pass; it tells visible frames
-- only, in creation order (a hidden frame hears when it is measured, or at the first pass after it shows); a change
-- seen while the frame holds no handler is spent, not replayed.
-- Cost: the pass walks the frames that ever held the script (w.onSizeChanged, not the whole script registry: retail
-- layer 287 of 5511 scripted objects) and resolves the (cached) rect of each visible one; hidden frames are most of
-- them (retail layer: 5 of 287 visible), so it skips their rects.
local M = {}

local Layout = require("ui.layout")

local NONE = 0

-- source: row LY13 (`ignoreRect`, default false), row LY5/LY6: with ignoreRect only the size the addon set counts;
-- otherwise a valid rect's size, else the set size, else a FontString's text size (row LY10), else 0.
function M.of(w, region, st, axis, ignoreRect)
  local rect = not ignoreRect and Layout.rect(w, region)
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

  return not ignoreRect and Layout.autoSize(w, region, axis, Layout.wrapWidth(w, region)) or NONE
end

-- Tells frame its size when it changed since it was last told; true when it did. The size is stored before the
-- handler runs, so a handler that measures the frame again is not told twice.
local function tell(w, frame)
  local st = w.ui.state[frame]
  if not st then
    return false
  end
  local width, height = M.of(w, frame, st, "x"), M.of(w, frame, st, "y")
  local layout = w.layout
  layout.told = layout.told or setmetatable({}, { __mode = "k" })
  local told = layout.told[frame] or { NONE, NONE }
  if told[1] == width and told[2] == height then
    return false
  end
  layout.told[frame] = { width, height }
  w:callScript(frame, "OnSizeChanged", width, height)

  return true
end

-- True when obj ever held the script: w.onSizeChanged outlives SetScript(nil) (world_events.lua scriptEntry).
local function watched(w, obj)
  return w.onSizeChanged[obj] == true
end

-- A measurement of region (GetWidth, GetRect, ...) resolved its rect: a frame that holds the script hears at once.
function M.measured(w, region)
  if watched(w, region) then
    tell(w, region)
  end
end

-- Shown, and every ancestor shown.
local function visible(w, st)
  while st do
    if not st.shown then
      return false
    end
    st = st.parent and w.ui.state[st.parent]
  end

  return true
end

-- The layout pass: every visible frame that ever held the script, in creation order. Returns how many were told.
function M.run(w)
  local state, frames = w.ui.state, {}
  for obj in pairs(w.onSizeChanged) do
    local st = state[obj]
    if st and visible(w, st) then
      frames[#frames + 1] = obj
    end
  end
  table.sort(frames, function(a, b)
    return state[a].seq < state[b].seq
  end)
  local count = 0
  for _, frame in ipairs(frames) do
    if tell(w, frame) then
      count = count + 1
    end
  end

  return count
end

return M
