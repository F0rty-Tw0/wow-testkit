-- Anchors and sizes resolved to rects. A region's pixel rect is { left, bottom, right, top } in physical pixels,
-- origin bottom-left; its rect is { left, bottom, width, height } in the units of its own effective scale space
-- (pixel = unit * GetEffectiveScale()). relativeTo == nil in an anchor means the screen, w.screen = { width, height }.
-- Results are cached per region against one world-wide version, w.layout.version: every layout-relevant mutation
-- bumps it, so a stale entry recomputes lazily (a superset of "this region and its dependants"). Rect tables are
-- cached and shared: callers read them, never write them.
local M = {}

local BehaviourRender = require("ui.behaviour_render")
local Callsite = require("ui.callsite")

-- Method names whose call changes layout; ui/widgets.lua bumps the version before running them.
M.MUTATORS = {}
for name in
  ("SetPoint SetAllPoints ClearAllPoints ClearPoint SetSize SetWidth SetHeight SetScale SetParent SetText SetFormattedText SetFont SetFontObject CopyFontObject SetWordWrap"):gmatch(
    "%S+"
  )
do
  M.MUTATORS[name] = true
end

-- source: row LY9, client error logs (Bartender4 issue 2278, AdiBags issue 680, Blizzard forum threads); the text
-- comes from the client's C side, so no Blizzard Lua shows it.
local ERROR_FORMAT = "Action[SetPoint] failed because[%s]: attempted from: %s:SetPoint."
M.CYCLE_REASON = "Cannot anchor to a region dependent on it"
M.SELF_REASON = "Cannot anchor to itself"

-- Point name -> { x alignment, y alignment }: 0 left/bottom, 1 right/top.
local ALIGN = {
  TOPLEFT = { 0, 1 },
  TOP = { 0.5, 1 },
  TOPRIGHT = { 1, 1 },
  LEFT = { 0, 0.5 },
  CENTER = { 0.5, 0.5 },
  RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 },
  BOTTOM = { 0.5, 0 },
  BOTTOMRIGHT = { 1, 0 },
}

-- A re-entrant resolve of one region means its data holds a cycle (SetPoint refuses them): that region has no rect.
local resolving = {}
local NO_RECT = {}

function M.install(w)
  w.layout = { version = 0, cache = setmetatable({}, { __mode = "k" }) }
end

-- Clears the cached rects of region and everything depending on it: one counter clears every region's cache.
function M.invalidate(w, _)
  w.layout.version = w.layout.version + 1
end

-- The size set on an axis, when it counts (Task 1.6 extends this for FontStrings).
local function explicitSize(st, axis)
  local size = axis == "x" and st.width or st.height
  return size and size > 0 and size or nil
end

-- assumed (row LY3): the screen target is the physical screen rect, whatever the region's scale.
local function targetPixels(w, anchor)
  local target = anchor[2]
  if target == nil then
    local screen = w.screen
    return screen and { left = 0, bottom = 0, right = screen.width, top = screen.height }
  end
  local targetState = w.ui.state[target]
  return targetState and M.entry(w, targetState).pixel
end

-- Where anchor lands in pixels, with the anchor point's alignments; nil when the point name or the target is bad.
local function anchorPosition(w, anchor, scale)
  local own, relative = ALIGN[anchor[1]], ALIGN[anchor[3]]
  local box = own and relative and targetPixels(w, anchor)
  if not box then
    return nil
  end
  return {
    x = box.left + relative[1] * (box.right - box.left) + anchor[4] * scale,
    y = box.bottom + relative[2] * (box.top - box.bottom) + anchor[5] * scale,
    ax = own[1],
    ay = own[2],
  }
end

-- One axis: low, high edge and whether the size came from the stored size.
-- source: wiki API_Region_SetWidth: "If the width/height is inferred from anchor points, then setting it has no
-- effect." (row LY5). Assumed (row LY5): one anchor plus a size places the region; fewer constraints give no rect.
local function solveAxis(points, pos, align, size, scale)
  local low, high
  for _, point in ipairs(points) do
    if point[align] == 0 and not low then
      low = point[pos]
    elseif point[align] == 1 and not high then
      high = point[pos]
    end
  end
  if low and high then
    return low, high, false
  end
  local first = points[1]
  if first and size then
    local edge = first[pos] - first[align] * size * scale
    return edge, edge + size * scale, true
  end
  return nil
end

local function compute(w, st)
  -- source: row LY7: offsets and sizes are in the region's own scale space, scale multiplies down the parent chain.
  local scale = BehaviourRender.effectiveScale(w, st)
  if scale <= 0 then
    return nil
  end
  local points = {}
  for i, anchor in ipairs(st.points) do
    points[i] = anchorPosition(w, anchor, scale)
    if not points[i] then
      return nil
    end
  end
  local left, right, widthSet = solveAxis(points, "x", "ax", explicitSize(st, "x"), scale)
  local bottom, top, heightSet = solveAxis(points, "y", "ay", explicitSize(st, "y"), scale)
  if not (left and bottom) then
    return nil
  end
  return {
    pixel = { left = left, bottom = bottom, right = right, top = top },
    rect = {
      left = left / scale,
      bottom = bottom / scale,
      width = widthSet and st.width or (right - left) / scale,
      height = heightSet and st.height or (top - bottom) / scale,
    },
  }
end

-- The cache entry { version, pixel, rect } of a region state, recomputed when its version is stale.
function M.entry(w, st)
  local layout = w.layout
  local hit = layout.cache[st]
  if hit and hit.version == layout.version then
    return hit
  end
  if resolving[st] then
    return NO_RECT
  end
  resolving[st] = true
  local result = compute(w, st) or NO_RECT
  resolving[st] = nil
  hit = { version = layout.version, pixel = result.pixel, rect = result.rect }
  layout.cache[st] = hit
  return hit
end

local function entryOf(w, region)
  local st = w.ui.state[region]
  return st and M.entry(w, st) or NO_RECT
end

function M.pixelRect(w, region)
  return entryOf(w, region).pixel
end

function M.rect(w, region)
  return entryOf(w, region).rect
end

-- True when from is region or anchors to it, directly or through other anchors.
local function dependsOn(w, from, region)
  local seen, stack = {}, { from }
  while #stack > 0 do
    local current = table.remove(stack)
    if current == region then
      return true
    end
    local st = not seen[current] and w.ui.state[current]
    seen[current] = true
    for _, anchor in ipairs(st and st.points or {}) do
      stack[#stack + 1] = anchor[2]
    end
  end
  return false
end

-- Raises the client's error when anchor (a parsed anchor record of region) would close a cycle or point at region.
-- Called before the anchor is stored, so a refused call leaves the old anchors.
function M.checkAnchor(w, region, anchor)
  local target = anchor[2]
  local reason
  if target == nil then
    return
  elseif target == region then
    reason = M.SELF_REASON
  elseif dependsOn(w, target, region) then
    reason = M.CYCLE_REASON
  else
    return
  end
  error(string.format(ERROR_FORMAT, reason, region:GetDebugName()), Callsite.level())
end

return M
