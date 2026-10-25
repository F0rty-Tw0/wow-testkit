-- The mouse-sensitive rect of a region: its screen rect (Layout.screenRect) with the hit insets applied, then
-- grown by IsMouseOver's offsets. All lengths are in the region's units, converted by its effective scale. Also which of
-- two frames draws above the other.
local M = {}

local BehaviourRender = require("ui.behaviour_render")
local Layout = require("ui.layout")

-- Frame strata, lowest first (wiki Frame_Strata, row LY12). An unknown strata ranks below all of them.
local STRATA_RANK = {}
for rank, name in ipairs({ "WORLD", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }) do
  STRATA_RANK[name] = rank
end

-- source: row LY11 (wiki API_Frame_SetHitRectInsets): positive insets shrink the hit rect on that side, negative ones
-- grow it. The insets are the generic SetHitRectInsets store { n, left, right, top, bottom }.
-- source: row LY11 (wiki API_ScriptRegion_IsMouseOver): positive offsetTop and offsetRight grow the rect up and
-- right, negative offsetBottom and offsetLeft grow it down and left. Assumed (row LY11): the offsets apply to the
-- hit rect, not the plain rect.
-- Returns { x, y, width, height } in physical pixels, origin top-left, or nil without a rect or an area.
function M.rect(w, region, top, bottom, left, right)
  local screen = Layout.screenRect(w, region)
  if not screen then
    return nil
  end
  local scale = BehaviourRender.effectiveScale(w, w.ui.state[region])
  local insets = w.ui.state[region].values.HitRectInsets or {}
  local x1 = screen.x + ((insets[1] or 0) + (left or 0)) * scale
  local x2 = screen.x + screen.width - ((insets[2] or 0) - (right or 0)) * scale
  local y1 = screen.y + ((insets[3] or 0) - (top or 0)) * scale
  local y2 = screen.y + screen.height - ((insets[4] or 0) + (bottom or 0)) * scale
  if x2 <= x1 or y2 <= y1 then
    return nil
  end
  return { x = x1, y = y1, width = x2 - x1, height = y2 - y1 }
end

-- True when the pixel x, y lies in the region's hit rect: x1 <= x < x2 and y1 <= y < y2 (assumed, row LY11).
function M.contains(w, region, x, y, top, bottom, left, right)
  local rect = M.rect(w, region, top, bottom, left, right)
  return rect ~= nil and x >= rect.x and x < rect.x + rect.width and y >= rect.y and y < rect.y + rect.height
end

-- source: row LY12: higher strata first, then higher frame level; the creation tie-break (later frame, st.seq) is
-- assumed, so equal frames never depend on pairs order. True when frame a draws above frame b.
function M.above(w, a, b)
  local rankA, rankB = STRATA_RANK[a:GetFrameStrata()] or 0, STRATA_RANK[b:GetFrameStrata()] or 0
  if rankA ~= rankB then
    return rankA > rankB
  end
  local levelA, levelB = a:GetFrameLevel(), b:GetFrameLevel()
  if levelA ~= levelB then
    return levelA > levelB
  end
  return w.ui.state[a].seq > w.ui.state[b].seq
end

return M
