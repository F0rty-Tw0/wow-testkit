-- Fields of a render snapshot item and the asset refs it emits (render_assets.lua).
local M = {}

local Assets = require("render_assets")
local BehaviourFontString = require("ui.behaviour_fontstring")
local BehaviourRender = require("ui.behaviour_render")
local BehaviourTexture = require("ui.behaviour_texture")
local FontChain = require("ui.font_chain")
local Layout = require("ui.layout")
local Read = require("render_read")
local RenderAnim = require("render_anim")
local Secret = require("combat_secret_value")
local TextState = require("ui.text_state")
local Widgets = require("render_widgets")

local ID_PREFIX = { frame = "f", texture = "t", fontstring = "s", backdrop = "b" }
local WHITE = { 1, 1, 1, 1 }
-- source: assumed (W29) the shadow colour GetShadowColor reports before one is set.
local NO_SHADOW = { 0, 0, 0, 0 }

M.refPath = Assets.refPath
M.refId = Assets.refId
M.refAtlas = Assets.refAtlas

-- "f3" for a frame, "b3.center" for the center piece of the backdrop of frame 3.
function M.id(entry)
  local suffix = entry.piece and "." .. entry.piece or ""

  return ID_PREFIX[entry.kind] .. entry.st.seq .. suffix
end

local addAtlas, addFont, addFile = Assets.addAtlas, Assets.addFont, Assets.addFile

local function copy(list)
  return { list[1], list[2], list[3], list[4], list[5], list[6], list[7], list[8] }
end

local function sameNumbers(list, default)
  for i = 1, #default do
    if list[i] ~= default[i] then
      return false
    end
  end

  return true
end

local function colorList(color)
  return { color[1], color[2], color[3], color[4] }
end

local function gradientOf(gradient)
  return { orientation = gradient.orientation, min = colorList(gradient.min), max = colorList(gradient.max) }
end

-- The source of a texture. The setters keep file, atlas and color exclusive (ui/behaviour_texture.lua), so it is the one
-- set last.
local function sourceFields(state, assets)
  local look = {}
  local atlas = state.atlas
  look.file = addFile(assets, state.file)
  look.atlas = type(atlas) == "string" and atlas ~= "" and addAtlas(assets, atlas) or nil
  look.color = state.color and colorList(state.color)

  return look
end

-- The texture fields of an item, each only when it differs from the client default: file or atlas or color, texCoord,
-- vertexColor, gradient, blendMode, desaturated, rotation, horizTile and vertTile. The slider thumb and the status bar
-- texture reuse it.
function M.look(_, st, assets)
  local state = Read.texture(st)
  local look = sourceFields(state, assets)
  if state.texCoord and not sameNumbers(state.texCoord, BehaviourTexture.FULL_IMAGE) then
    look.texCoord = copy(state.texCoord)
  end
  if state.vertexColor and not sameNumbers(state.vertexColor, BehaviourTexture.WHITE) then
    look.vertexColor = colorList(state.vertexColor)
  end
  look.gradient = state.gradient and gradientOf(state.gradient)
  if state.blend ~= nil and state.blend ~= BehaviourTexture.DEFAULT_BLEND then
    look.blendMode = state.blend
  end
  look.desaturated = state.desaturated or nil
  look.rotation = state.rotation ~= 0 and state.rotation or nil
  look.horizTile = state.horizTile or nil
  look.vertTile = state.vertTile or nil

  return look
end

-- Registers the textures and atlases a text names: "|T<path>:..|t" and "|A:<atlas>:..|a". "||" is a pipe, not an escape.
local function addEscapes(assets, text)
  local plain = text:gsub("||", "")
  for target in plain:gmatch("|T([^:|]+)") do
    addFile(assets, tonumber(target) or target)
  end
  for atlas in plain:gmatch("|A:([^:|]+)") do
    addAtlas(assets, atlas)
  end
end

local function shadowOf(w, st)
  local offset, color = TextState.shadowOffset(w, st), TextState.shadowColor(w, st)
  if not (offset or color) then
    return nil
  end
  return { color = Read.color(color, NO_SHADOW), x = offset and offset[1] or 0, y = offset and offset[2] or 0 }
end

local function fontFields(w, st, item, assets)
  local font = FontChain.inherited(w, st, "font")
  if font and type(font[1]) == "string" then
    item.font = addFont(assets, font[1])
    item.size = font[2]
    item.flags = font[3]
  end
  item.text = Secret.text(st.text)
  if item.text then
    addEscapes(assets, item.text)
  end
  item.color = Read.color(FontChain.inherited(w, st, "textColor"), WHITE)
end

local function fontStringFields(w, obj, st, item, assets)
  fontFields(w, st, item, assets)
  item.justifyH = TextState.justifyH(w, st)
  item.justifyV = TextState.justifyV(w, st)
  item.shadow = shadowOf(w, st)
  item.wrap = TextState.wordWrap(st)
  item.maxLines = TextState.maxLines(st)
  item.spacing = TextState.spacing(w, st)
  item.truncated = BehaviourFontString.isTruncated(w, obj) or nil
end

-- What the widget exporters (render_widgets_range.lua) need from this file: the texture fields of a region state and the
-- item id of a frame.
function M.context(w, assets)
  return {
    look = function(regionState)
      return M.look(w, regionState, assets)
    end,
    frameId = function(frame)
      return M.id({ kind = "frame", st = w.ui.state[frame] })
    end,
  }
end

-- A backdrop piece: the whole backdrop data, drawn in the layer of the piece, with the frame as its parent.
local function backdropPiece(w, entry, assets)
  return {
    id = M.id(entry),
    kind = entry.kind,
    piece = entry.piece,
    parent = M.id({ kind = "frame", st = entry.st }),
    rect = entry.rect,
    clip = entry.clip,
    alpha = BehaviourRender.effectiveAlpha(w, entry.obj),
    layer = entry.layer,
    sublevel = 0,
    backdrop = Widgets.backdrop(w, entry.st, assets),
  }
end

-- entry.rect and entry.clip are set by the caller (render.lua).
local function build(w, entry, assets)
  if entry.kind == "backdrop" then
    return backdropPiece(w, entry, assets)
  end
  local st = entry.st
  local parent = st.parent and w.ui.state[st.parent]
  local item = {
    id = M.id(entry),
    kind = entry.kind,
    name = st.name,
    parent = parent and M.id({ kind = "frame", st = parent }),
    rect = entry.rect,
    clip = entry.clip,
    alpha = BehaviourRender.effectiveAlpha(w, entry.obj),
  }
  if entry.kind == "frame" then
    item.strata = BehaviourRender.methods.GetFrameStrata(w, entry.obj, st)
    item.level = BehaviourRender.methods.GetFrameLevel(w, entry.obj, st)
    item.widget = Widgets.state(w, entry.obj, st, M.context(w, assets))
    return item
  end
  local layer = Read.stored(st, "DrawLayer")
  item.layer, item.sublevel = layer and layer[1] or "ARTWORK", layer and layer[2] or 0
  if entry.kind == "texture" then
    for key, value in pairs(M.look(w, st, assets)) do
      item[key] = value
    end
  else
    fontStringFields(w, entry.obj, st, item, assets)
    item.autoWidth = Layout.autoWidth(w, entry.obj) or nil
  end
  return item
end

-- The item of entry, with the playing animations applied (render_anim.lua).
function M.item(w, entry, assets)
  local item = build(w, entry, assets)
  RenderAnim.apply(w, entry.obj, item)

  return item
end

return M
