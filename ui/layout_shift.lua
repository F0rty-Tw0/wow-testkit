-- Extra offset a region's anchors get on top of the offsets set on them, in the region's own units. Layout adds it
-- to every anchor (ui/layout.lua). Two things move: the button text shifts by the pushed text offset while its button
-- is PUSHED, and the scroll child of a ScrollFrame shifts by its scroll offsets. Reads kit state only, so it needs none
-- of the behaviour modules (they require Layout).
local M = {}

-- source: assumed (W20) no source states the default pushed text offset; 1, -1 is the value that fits the extract.
M.DEFAULT_PUSHED_OFFSET = { 1, -1 }

local NO_SHIFT = 0

-- The pushed text offset of a button state (st.btn): its own, else the default.
function M.pushedOffset(btn)
  local offset = btn and btn.offset or M.DEFAULT_PUSHED_OFFSET

  return offset[1], offset[2]
end

-- source: assumed (W45) the scroll child moves by (-horizontal, +vertical): scrolling down moves the content up.
local function scrollShift(parent, obj)
  local scroll = parent and parent.scroll
  if not (scroll and scroll.child == obj) then
    return nil
  end

  return -scroll.h, scroll.v
end

-- dx, dy for the region obj with state st; 0, 0 unless it is the text of a PUSHED button or the child of a ScrollFrame.
function M.of(w, obj, st)
  local parent = st.parent and w.ui.state[st.parent]
  local scrollX, scrollY = scrollShift(parent, obj)
  if scrollX then
    return scrollX, scrollY
  end
  local btn = parent and parent.btn
  if not (btn and btn.fs == obj and btn.state == "PUSHED") then
    return NO_SHIFT, NO_SHIFT
  end

  return M.pushedOffset(btn)
end

return M
