-- Render snapshot: the visible frames, textures and font strings of a world as plain data (see Json.encode), in draw
-- order, with screen-pixel rects (origin top-left), clips and the assets they name. Reads only kit state.
local M = {}

local BehaviourRender = require("ui.behaviour_render")
local Fields = require("render_fields")
local Finite = require("render_finite")
local Json = require("json")
local Layout = require("ui.layout")
local Order = require("render_order")
local Read = require("render_read")

local SNAPSHOT_VERSION = 1

-- UIParent's effective scale, 1 without UIParent.
local function screenScale(w)
  local uiParent = rawget(_G, "UIParent")
  local st = uiParent ~= nil and w.ui.state[uiParent]
  return st and BehaviourRender.effectiveScale(w, st) or 1
end

local function copyErrors(w)
  local errors = {}
  for i, err in ipairs(w.errors) do
    errors[i] = { message = err.message, traceback = err.traceback }
  end
  return errors
end

local function intersect(a, b)
  local left, top = math.max(a.x, b.x), math.max(a.y, b.y)
  local right, bottom = math.min(a.x + a.width, b.x + b.width), math.min(a.y + a.height, b.y + b.height)
  return { x = left, y = top, width = math.max(0, right - left), height = math.max(0, bottom - top) }
end

-- source: row V10 is assumed (no source states the rule): SetClipsChildren(true) and a ScrollFrame clip every
-- descendant, frames and regions, to the clipping frame's rect.
local function clipsChildren(st)
  local pack = Read.stored(st, "ClipsChildren")
  return st.plan.isA.scrollframe == true or (pack ~= nil and pack[1] == true)
end

-- The intersection of the screen rects of every clipping ancestor of entry (a region's own frame included); nil when
-- none clips. An ancestor without a rect, or with a non-finite one, clips nothing.
local function clipOf(w, entry)
  local clip
  local ancestor = entry.st.parent
  local st = ancestor and w.ui.state[ancestor]
  while st do
    local rect = clipsChildren(st) and Layout.screenRect(w, ancestor)
    if rect and Finite.rect(rect) then
      clip = clip and intersect(clip, rect) or rect
    end
    ancestor = st.parent
    st = ancestor and w.ui.state[ancestor]
  end
  return clip
end

local function build(w)
  local assets = Json.object({})
  local items, unplaced = {}, {}
  for _, entry in ipairs(Order.collect(w)) do
    entry.rect = Layout.screenRect(w, entry.obj)
    if entry.rect and Finite.rect(entry.rect) then
      entry.clip = clipOf(w, entry)
      items[#items + 1] = Fields.item(w, entry, assets)
    else
      unplaced[#unplaced + 1] = { id = Fields.id(entry), name = entry.st.name, kind = entry.kind }
    end
  end
  local screen = { width = w.screen.width, height = w.screen.height, scale = screenScale(w) }
  return { ver = SNAPSHOT_VERSION, screen = screen, items = items, unplaced = unplaced, errors = copyErrors(w), assets = assets }
end

-- The render snapshot of w. It reads kit state directly, never an addon-facing method, so w.unscripted stays as it
-- was (tests/test_render.lua and test_render_widgets.lua pin that). Json.encode accepts the result whatever numbers the
-- addon stored.
function M.snapshot(w)
  return Finite.scrub(build(w))
end

return M
