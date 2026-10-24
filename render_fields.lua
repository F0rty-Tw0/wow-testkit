-- Fields of a render snapshot item and the asset refs it emits. Ref keys: a path -> "path:" + lowercase with "/"; a
-- number -> "id:<n>"; an atlas -> "atlas:" + lowercase; a font file -> "font:" + the path as for "path:".
-- assets[ref] = { kind = "path"|"fileID"|"atlas"|"font", path?, fileID?, atlas? } where path and atlas keep the
-- addon's spelling (path with "/"). Mirrored in viewer.js.
local M = {}

local BehaviourRender = require("ui.behaviour_render")
local FontChain = require("ui.font_chain")
local Read = require("render_read")

local ID_PREFIX = { frame = "f", texture = "t", fontstring = "s" }
local WHITE = { 1, 1, 1, 1 }
local BLACK = { 0, 0, 0, 1 }

-- source: row V11, wiki XML/FontString attribute defaults: justifyH CENTER, justifyV MIDDLE, wordwrap true,
-- maxLines 0, spacing 0. That a CreateFontString object has the same defaults is assumed.
local DEFAULT_JUSTIFY_H, DEFAULT_JUSTIFY_V = "CENTER", "MIDDLE"
local DEFAULT_MAX_LINES, DEFAULT_SPACING = 0, 0

local function slashed(path)
  return (path:gsub("\\", "/"))
end

function M.refPath(path)
  return "path:" .. slashed(path):lower()
end

function M.refId(n)
  return "id:" .. string.format("%.14g", n)
end

function M.refAtlas(atlas)
  return "atlas:" .. atlas:lower()
end

local function refFont(path)
  return "font:" .. slashed(path):lower()
end

function M.id(entry)
  return ID_PREFIX[entry.kind] .. entry.st.seq
end

local function addPath(assets, path)
  local ref = M.refPath(path)
  assets[ref] = assets[ref] or { kind = "path", path = slashed(path) }
  return ref
end

local function addAtlas(assets, atlas)
  local ref = M.refAtlas(atlas)
  assets[ref] = assets[ref] or { kind = "atlas", atlas = atlas }
  return ref
end

local function addFont(assets, path)
  local ref = refFont(path)
  assets[ref] = assets[ref] or { kind = "font", path = slashed(path) }
  return ref
end

-- The ref of a texture path or fileID, registering it; nil for anything else (nil, "", a table).
local function addFile(assets, file)
  if type(file) == "number" then
    local ref = M.refId(file)
    assets[ref] = assets[ref] or { kind = "fileID", fileID = file }
    return ref
  elseif type(file) == "string" and file ~= "" then
    return addPath(assets, file)
  end
  return nil
end

local function numbers(pack)
  local list = {}
  for i = 1, pack.n do
    list[i] = pack[i]
  end
  return list
end

local function colorOf(value)
  return { value.r, value.g, value.b, value.a or 1 }
end

-- SetGradient(orientation, minColor, maxColor) with color tables, or the Classic form with minR, minG, minB, maxR, maxG, maxB.
local function gradientOf(pack)
  if type(pack[2]) == "table" then
    return { orientation = pack[1], min = colorOf(pack[2]), max = colorOf(pack[3]) }
  end
  return { orientation = pack[1], min = { pack[2], pack[3], pack[4], 1 }, max = { pack[5], pack[6], pack[7], 1 } }
end

local function copyStored(item, field, st, key)
  local pack = Read.stored(st, key)
  if pack then
    item[field] = pack[1]
  end
end

local function textureFields(st, item, assets)
  local file = Read.stored(st, "Texture")
  item.file = file and addFile(assets, file[1])
  local atlas = Read.stored(st, "Atlas")
  if atlas and type(atlas[1]) == "string" and atlas[1] ~= "" then
    item.atlas = addAtlas(assets, atlas[1])
  end
  local color = Read.stored(st, "ColorTexture")
  item.color = color and Read.color(color)
  local texCoord = Read.stored(st, "TexCoord")
  item.texCoord = texCoord and numbers(texCoord)
  local vertexColor = Read.stored(st, "VertexColor")
  item.vertexColor = vertexColor and Read.color(vertexColor)
  local gradient = Read.stored(st, "Gradient")
  item.gradient = gradient and gradientOf(gradient)
  copyStored(item, "blendMode", st, "BlendMode")
  copyStored(item, "desaturated", st, "Desaturated")
  copyStored(item, "rotation", st, "Rotation")
  copyStored(item, "horizTile", st, "HorizTile")
  copyStored(item, "vertTile", st, "VertTile")
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

local function shadowOf(st)
  local offset, color = Read.stored(st, "ShadowOffset"), Read.stored(st, "ShadowColor")
  if not (offset or color) then
    return nil
  end
  return { color = Read.color(color, BLACK), x = offset and offset[1] or 0, y = offset and offset[2] or 0 }
end

local function fontFields(w, st, item, assets)
  local font = FontChain.inherited(w, st, "font")
  if font and type(font[1]) == "string" then
    item.font = addFont(assets, font[1])
    item.size = font[2]
    item.flags = font[3]
  end
  item.text = st.text
  if st.text then
    addEscapes(assets, st.text)
  end
  item.color = Read.color(FontChain.inherited(w, st, "textColor"), WHITE)
end

local function fontStringFields(w, st, item, assets)
  fontFields(w, st, item, assets)
  local justifyH, justifyV = Read.stored(st, "JustifyH"), Read.stored(st, "JustifyV")
  item.justifyH = justifyH and justifyH[1] or DEFAULT_JUSTIFY_H
  item.justifyV = justifyV and justifyV[1] or DEFAULT_JUSTIFY_V
  item.shadow = shadowOf(st)
  local wrap = Read.stored(st, "WordWrap")
  item.wrap = wrap == nil or wrap[1] and true or false
  local maxLines, spacing = Read.stored(st, "MaxLines"), Read.stored(st, "Spacing")
  item.maxLines = maxLines and maxLines[1] or DEFAULT_MAX_LINES
  item.spacing = spacing and spacing[1] or DEFAULT_SPACING
end

-- entry.rect and entry.clip are set by the caller (render.lua).
function M.item(w, entry, assets)
  local st = entry.st
  local parent = st.parent and w.ui.state[st.parent]
  local item = {
    id = M.id(entry),
    kind = entry.kind,
    name = st.name,
    parent = parent and M.id({ kind = "frame", st = parent }),
    rect = entry.rect,
    clip = entry.clip,
    alpha = BehaviourRender.methods.GetEffectiveAlpha(w, entry.obj, st),
  }
  if entry.kind == "frame" then
    item.strata = BehaviourRender.methods.GetFrameStrata(w, entry.obj, st)
    item.level = BehaviourRender.methods.GetFrameLevel(w, entry.obj, st)
    return item
  end
  local layer = Read.stored(st, "DrawLayer")
  item.layer, item.sublevel = layer and layer[1] or "ARTWORK", layer and layer[2] or 0
  if entry.kind == "texture" then
    textureFields(st, item, assets)
  else
    fontStringFields(w, st, item, assets)
  end
  return item
end

return M
