-- What layout uses for a region that sets none of its own: the anchors of a region with no points, and the size of an
-- axis with no size set. Reads kit state only (ui/layout.lua requires it).
local M = {}

local Shift = require("ui.layout_shift")

-- The anchors of region: the ones set on it; with none, a fill-the-parent texture's two corners on its parent's, and a
-- ScrollFrame's scroll child's top-left corner on the frame's.
-- source: blizzard_sharedxml/securescrolltemplates.xml:160-168 (`FauxScrollFrameTemplate`) declares its scroll child with a
-- `<Size>` and no `<Anchors>`; assumed (W45) the frame places such a child at its own top-left.
-- source: assumed (row X28) the fill is a default, not two stored points: the first SetPoint replaces it, and
-- GetNumPoints answers 0 until then.
function M.anchors(w, region, st)
  local parent = st.parent
  if #st.points > 0 or not parent then
    return st.points
  end
  if st.fillsParent then
    return { { "TOPLEFT", parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0 } }
  end
  if Shift.isScrollChild(w.ui.state[parent], region) then
    return { { "TOPLEFT", parent, "TOPLEFT", 0, 0 } }
  end

  return st.points
end

-- The size on axis a fill-the-parent texture with no size of its own falls back to: its parent's pixel span (parentPixel,
-- nil when the parent has no rect) in the texture's units (scale); nil for any other region.
-- source: assumed (row X28) the texture keeps its parent's size once anchored by one point: the classic pressed-button
-- idiom moves such a texture by its TOPLEFT alone (tbc 70577 blizzard_characterframe/cata/paperdollframe.xml:242-246,
-- the anchorless DeleteButton texture), which reads as a press only if the texture keeps its size.
function M.size(parentPixel, axis, scale)
  if not parentPixel then
    return nil
  end
  local span = parentPixel.top - parentPixel.bottom
  if axis == "x" then
    span = parentPixel.right - parentPixel.left
  end

  return span / scale
end

return M
