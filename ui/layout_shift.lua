-- Extra offset a region's anchors get on top of the offsets set on them, in the region's own units. Layout adds it
-- to every anchor (ui/layout.lua). Only the button text moves so far: it shifts by the pushed text offset while its
-- button is PUSHED. Task 6.6 adds the scroll offset of a scroll child here. Reads kit state only, so it needs none of
-- the behaviour modules (they require Layout).
local M = {}

-- source: assumed (W20) no source states the default pushed text offset; 1, -1 is the value that fits the extract.
M.DEFAULT_PUSHED_OFFSET = { 1, -1 }

local NO_SHIFT = 0

-- The pushed text offset of a button state (st.btn): its own, else the default.
function M.pushedOffset(btn)
  local offset = btn and btn.offset or M.DEFAULT_PUSHED_OFFSET

  return offset[1], offset[2]
end

-- dx, dy for the region obj with state st; 0, 0 unless it is the text of a PUSHED button.
function M.of(w, obj, st)
  local parent = st.parent and w.ui.state[st.parent]
  local btn = parent and parent.btn
  if not (btn and btn.fs == obj and btn.state == "PUSHED") then
    return NO_SHIFT, NO_SHIFT
  end

  return M.pushedOffset(btn)
end

return M
