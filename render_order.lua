-- Draw order of the render snapshot: every visible frame, texture and font string, back to front.
local M = {}

local Behaviour = require("ui.behaviour")
local BehaviourButton = require("ui.behaviour_button")
local BehaviourRender = require("ui.behaviour_render")
local Read = require("render_read")

-- source: row V5, wiki Layer, "the five named layers, in the order they are drawn (back to front)".
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local DEFAULT_LAYER = LAYERS.ARTWORK
local DEFAULT_SUBLEVEL = 0

local FRAME_PART, REGION_PART = 0, 1
local TEXTURE_RANK, FONT_STRING_RANK = 0, 1
local REGION_KINDS = { Texture = "texture", FontString = "fontstring" }

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

-- source: row V9, wiki Layer, Details: "Setting Frame:EnableMouse() causes HIGHLIGHT to show/hide as the cursor hovers
-- the Frame." A HIGHLIGHT region draws while the mouse focus is its frame or a descendant of it; a button's draws by
-- BehaviourButton.highlightShown instead (W17), and a state texture of a button only in its state (W17, W24). A slider
-- thumb or status bar texture never draws as a region: its widget exports it (W43, W44).
local function regionDraws(w, st)
  local owner = st.parent
  if st.widgetPart then
    return false
  end
  if st.role and not BehaviourButton.shown(w, owner, st.role) then
    return false
  end
  if layerOf(st) ~= "HIGHLIGHT" then
    return true
  end
  if w.ui.state[owner].plan.isA.button then
    return BehaviourButton.highlightShown(w, owner)
  end

  return BehaviourButton.mouseWithin(w, owner)
end

-- Splits the visible objects of w.ui.state into frames (obj -> frameKey) and region entries { obj, st, kind }.
local function visibleObjects(w)
  local frames, regions = {}, {}
  for obj, st in pairs(w.ui.state) do
    if Behaviour.methods.IsVisible(w, obj, st) then
      if st.plan.isFrame then
        frames[obj] = BehaviourRender.frameKey(w, obj, st)
      elseif REGION_KINDS[st.plan.type] then
        regions[#regions + 1] = { obj = obj, st = st, kind = REGION_KINDS[st.plan.type] }
      end
    end
  end
  return frames, regions
end

-- source: row V4, Backdrop.lua:326 and NineSlice.lua:168: the backdrop's Center texture is in BACKGROUND and its edge pieces
-- default to BORDER. Assumed (no source): sublevel 0, and a piece draws below a region of its layer and sublevel, since
-- the frame is created before its regions. Backdrop.lua:255-265: the Center's texture is bgFile and each edge piece's is
-- edgeFile, so a piece whose file is unset draws nothing and is not exported.
local BACKDROP_PIECES = {
  { piece = "center", layer = "BACKGROUND", file = "bgFile" },
  { piece = "edge", layer = "BORDER", file = "edgeFile" },
}

-- The entries { obj = frame, st, kind = "backdrop", piece, layer, key } of the backdrop of a frame, none without one.
local function backdropEntries(obj, st, frameKeys)
  local entries = {}
  if not st.backdrop then
    return entries
  end
  for _, part in ipairs(BACKDROP_PIECES) do
    if st.backdrop.info[part.file] then
      local key = { frameKeys[1], frameKeys[2], frameKeys[3], REGION_PART, LAYERS[part.layer], TEXTURE_RANK, DEFAULT_SUBLEVEL, st.seq }
      entries[#entries + 1] = { obj = obj, st = st, kind = "backdrop", piece = part.piece, layer = part.layer, key = key }
    end
  end

  return entries
end

-- Every visible frame, backdrop piece, texture and font string of w.ui.state as { obj, st, kind, key }, back to front.
function M.collect(w)
  local frames, regions = visibleObjects(w)
  local entries = {}
  for obj, key in pairs(frames) do
    local st = w.ui.state[obj]
    local frameOnly = { key[1], key[2], key[3], FRAME_PART, 0, 0, 0, 0 }
    entries[#entries + 1] = { obj = obj, st = st, kind = "frame", key = frameOnly }
    for _, piece in ipairs(backdropEntries(obj, st, key)) do
      entries[#entries + 1] = piece
    end
  end
  for _, entry in ipairs(regions) do
    local parentKey = frames[entry.st.parent]
    if parentKey and regionDraws(w, entry.st) then
      entry.key = regionKey(parentKey, entry.st, entry.kind)
      entries[#entries + 1] = entry
    end
  end
  table.sort(entries, precedes)
  return entries
end

return M
