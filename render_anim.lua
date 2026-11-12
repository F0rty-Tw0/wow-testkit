-- Playing animations in a render snapshot item: an Alpha sets the target's alpha, its rect is moved and scaled, and a
-- texture is rotated and stepped through its FlipBook frames. Descendants of a target inherit its alpha and translation.
-- Reads w.now through ui/anim.lua; never schedules or advances the clock. Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local M = {}

local Anim = require("ui.anim")
local AnimEffects = require("ui.anim_effects")

-- source: assumed (W61 W62) descendants of the target inherit its alpha animation (up to a region that ignores its
-- parent's alpha) and its translation.
-- { alpha, dx, dy } over obj and its ancestors, and obj's own effects. alpha is the effective alpha with each animated
-- region's own alpha replaced by its animation's (W61).
local function climb(w, obj)
  local total = { alpha = 1, dx = 0, dy = 0 }
  local own
  local alphaOpen = true
  local current = obj
  while current do
    local st = w.ui.state[current]
    local fx = AnimEffects.effects(w, current)
    if current == obj then
      own = fx
    end
    if alphaOpen then
      total.alpha = total.alpha * (fx and fx.setsAlpha and fx.alpha or st.alpha or 1)
    end
    if fx then
      total.dx = total.dx + fx.dx
      total.dy = total.dy + fx.dy
    end
    alphaOpen = alphaOpen and not st.ignoreAlpha
    current = st.parent
  end

  return total, own
end

-- rect scaled by sx, sy about the point of origin (its pivot on the rect plus the offsets, y up).
local function scaled(rect, entry)
  local pivot = Anim.pivot(entry.point)
  local px = rect.x + pivot[1] * rect.width + entry.ox
  local py = rect.y + pivot[2] * rect.height - entry.oy

  return {
    x = px + (rect.x - px) * entry.x,
    y = py + (rect.y - py) * entry.y,
    width = rect.width * entry.x,
    height = rect.height * entry.y,
  }
end

local FULL_IMAGE = { 0, 0, 0, 1, 1, 0, 1, 1 }

-- The corner form (UL, LL, UR, LR) of the cell of texCoord: each cell corner is a point of the shown region, mapped
-- bilinearly through texCoord's corners, so a cropped, flipped or skewed texture keeps its shape.
local function cellCoords(texCoord, cell)
  local c = texCoord or FULL_IMAGE
  local function at(u, v)
    local a, b, d, e = (1 - u) * (1 - v), (1 - u) * v, u * (1 - v), u * v

    return a * c[1] + b * c[3] + d * c[5] + e * c[7], a * c[2] + b * c[4] + d * c[6] + e * c[8]
  end
  local ulx, uly = at(cell.left, cell.top)
  local llx, lly = at(cell.left, cell.bottom)
  local urx, ury = at(cell.right, cell.top)
  local lrx, lry = at(cell.right, cell.bottom)

  return { ulx, uly, llx, lly, urx, ury, lrx, lry }
end

-- Changes item (a fresh table: the rect is replaced, never edited) for the animations playing on obj and its ancestors.
function M.apply(w, obj, item)
  if not AnimEffects.anyActive(w) then
    return
  end
  local total, own = climb(w, obj)
  item.alpha = total.alpha
  local rect = item.rect
  for _, entry in ipairs(own and own.scales or {}) do
    rect = scaled(rect, entry)
  end
  if total.dx ~= 0 or total.dy ~= 0 then
    rect = { x = rect.x + total.dx, y = rect.y - total.dy, width = rect.width, height = rect.height }
  end
  item.rect = rect
  -- source: assumed (W63) frames cannot rotate, so only a texture shows a Rotation animation.
  if item.kind == "texture" and own and own.rotation ~= 0 then
    item.rotation = (item.rotation or 0) + own.rotation
  end
  if item.kind == "texture" and own and own.cell then
    item.texCoord = cellCoords(item.texCoord, own.cell)
  end
end

return M
