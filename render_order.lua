-- Draw order of the render snapshot: every visible frame, texture and font string, back to front.
local M = {}

local Behaviour = require("ui.behaviour")
local BehaviourRender = require("ui.behaviour_render")
local Read = require("render_read")

-- source: row V1, wiki Frame_Strata, "from back to front": BACKGROUND, LOW, MEDIUM, HIGH, DIALOG, FULLSCREEN,
-- FULLSCREEN_DIALOG, TOOLTIP. WORLD is reserved for the world frame and cannot be assigned, so it stays out.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- source: row V5, wiki Layer, "the five named layers, in the order they are drawn (back to front)".
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local DEFAULT_STRATA = STRATA.MEDIUM
local DEFAULT_LAYER = LAYERS.ARTWORK
local DEFAULT_SUBLEVEL = 0

local FRAME_PART, REGION_PART = 0, 1
local TEXTURE_RANK, FONT_STRING_RANK = 0, 1
local REGION_KINDS = { Texture = "texture", FontString = "fontstring" }

-- source: row V9, wiki Layer, Details: "Setting Frame:EnableMouse() causes HIGHLIGHT to show/hide as the cursor hovers
-- the Frame." A HIGHLIGHT region draws while the mouse focus is its frame or a descendant of it.
local function mouseIsOver(w, frame)
  local cursor = w.input and w.input.mouseFocus
  while cursor do
    if cursor == frame then
      return true
    end
    local st = w.ui.state[cursor]
    cursor = st and st.parent
  end
  return false
end

-- The sort keys of a frame: { strata, level, seq } of a frame, read from kit state.
local function frameKey(w, obj, st)
  local strata = BehaviourRender.methods.GetFrameStrata(w, obj, st)
  return { STRATA[strata] or DEFAULT_STRATA, BehaviourRender.methods.GetFrameLevel(w, obj, st), st.seq }
end

-- The layer index and sublevel of a region from its stored DrawLayer pack.
local function layerOf(st)
  local pack = Read.stored(st, "DrawLayer")
  local layer = pack and pack[1]
  return layer or "ARTWORK", pack and pack[2] or DEFAULT_SUBLEVEL
end

-- source: row V6, wiki API:Frame_CreateFontString: "FontStrings do not support sublayers, and will always be drawn
-- above textures sharing the same layer." So a FontString ranks after the textures of its layer and its stored
-- sublevel never sorts. Equal layer and sublevel: the later-created region draws above (row V7, assumed).
local function regionKey(frameKeys, st, kind)
  local layer, sublevel = layerOf(st)
  local rank, sortLevel = TEXTURE_RANK, sublevel
  if kind == "fontstring" then
    rank, sortLevel = FONT_STRING_RANK, DEFAULT_SUBLEVEL
  end
  return { frameKeys[1], frameKeys[2], frameKeys[3], REGION_PART, LAYERS[layer] or DEFAULT_LAYER, rank, sortLevel, st.seq }
end

local function precedes(a, b)
  for i = 1, #a.key do
    if a.key[i] ~= b.key[i] then
      return a.key[i] < b.key[i]
    end
  end
  return false
end

-- Splits the visible objects of w.ui.state into frames (obj -> frameKey) and region entries { obj, st, kind }.
local function visibleObjects(w)
  local frames, regions = {}, {}
  for obj, st in pairs(w.ui.state) do
    if Behaviour.methods.IsVisible(w, obj, st) then
      if st.plan.isFrame then
        frames[obj] = frameKey(w, obj, st)
      elseif REGION_KINDS[st.plan.type] then
        regions[#regions + 1] = { obj = obj, st = st, kind = REGION_KINDS[st.plan.type] }
      end
    end
  end
  return frames, regions
end

-- Every visible frame, texture and font string of w.ui.state as { obj, st, kind, key }, back to front.
function M.collect(w)
  local frames, regions = visibleObjects(w)
  local entries = {}
  for obj, key in pairs(frames) do
    local frameOnly = { key[1], key[2], key[3], FRAME_PART, 0, 0, 0, 0 }
    entries[#entries + 1] = { obj = obj, st = w.ui.state[obj], kind = "frame", key = frameOnly }
  end
  for _, entry in ipairs(regions) do
    local parentKey = frames[entry.st.parent]
    local layer = layerOf(entry.st)
    if parentKey and (layer ~= "HIGHLIGHT" or mouseIsOver(w, entry.st.parent)) then
      entry.key = regionKey(parentKey, entry.st, entry.kind)
      entries[#entries + 1] = entry
    end
  end
  table.sort(entries, precedes)
  return entries
end

return M
