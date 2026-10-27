-- Hand-written texture behaviour. A texture's state is st.tex = { file, atlas, color, texCoord, vertexColor, gradient,
-- blend, desaturated, rotation, horizTile, vertTile, masks }, each key present only once set; the getters answer the
-- client default for a key never set. The texture methods register through Typed.add for TextureBase (masks for
-- Texture), so a type with a same-named method of its own keeps its body. M.methods carries the region methods:
-- SetDrawLayer's sublevel clamp and the ignore-parent flags (st.ignoreAlpha, st.ignoreScale, read by
-- ui/behaviour_render.lua). Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Client = require("client")
local Typed = require("ui.typed")

local select = select
local unpack = unpack

local methods = {}
M.methods = methods

M.FULL_IMAGE = { 0, 0, 0, 1, 1, 0, 1, 1 }
M.WHITE = { 1, 1, 1, 1 }
M.DEFAULT_BLEND = "BLEND"
M.NO_TEXTURE = {}

local DEFAULT_ALPHA = 1
local TEX_COORD_LENGTH = 8
local MIN_SUBLEVEL, MAX_SUBLEVEL, DEFAULT_SUBLEVEL = -8, 7, 0

-- The state set so far; M.NO_TEXTURE (never written) for a texture nothing was set on.
function M.read(st)
  return st.tex or M.NO_TEXTURE
end

local function write(st)
  st.tex = st.tex or {}

  return st.tex
end

-- Source -------------------------------------------------------------------------------------------------------

-- source: assumed (W1) the last of SetTexture, SetColorTexture and SetAtlas wins and the earlier two no longer read back.
local function clearSources(state)
  state.file, state.atlas, state.color = nil, nil, nil
end

-- source: wiki API_TextureBase_SetTexture (row W1): "To clear the texture call this without any params or nil".
local function setTexture(_, _, st, file)
  local state = write(st)
  clearSources(state)
  state.file = file
end

-- source: W12, wiki API_TextureBase_SetColorTexture, alpha `= 1`.
local function setColorTexture(_, _, st, r, g, b, a)
  local state = write(st)
  clearSources(state)
  state.color = { r, g, b, a or DEFAULT_ALPHA }
end

-- source: W3, api/retail/SimpleTextureBaseAPI.lua:401 and wiki API_TextureBase_SetAtlas: useAtlasSize sizes the region
-- to the atlas; it needs a client extract to know the size.
local function setAtlas(w, obj, st, atlas, useAtlasSize)
  local state = write(st)
  clearSources(state)
  state.atlas = atlas
  local row = useAtlasSize and w.client and type(atlas) == "string" and Client.atlas(w.client, atlas)
  if row then
    obj:SetSize(row.width, row.height)
  end
end

-- Tex coords and colours --------------------------------------------------------------------------------------

-- source: W4, blizzard_sharedxml/nineslice.lua:78 (`SetTexCoord(left, right, top, bottom)`) and
-- blizzard_sharedxml/backdrop.lua:215 (the eight values UL, LL, UR, LR); W5 eight arguments are stored as given.
local function setTexCoord(_, _, st, ...)
  local given = { ... }
  if select("#", ...) >= TEX_COORD_LENGTH then
    write(st).texCoord = { unpack(given, 1, TEX_COORD_LENGTH) }

    return
  end
  local left, right, top, bottom = ...
  write(st).texCoord = { left, top, left, bottom, right, top, right, bottom }
end

local function getTexCoord(_, _, st)
  return unpack(M.read(st).texCoord or M.FULL_IMAGE, 1, TEX_COORD_LENGTH)
end

-- source: W6, wiki API_Region_SetVertexColor, alpha `= 1.0`.
local function setVertexColor(_, _, st, r, g, b, a)
  write(st).vertexColor = { r, g, b, a or DEFAULT_ALPHA }
end

local function getVertexColor(_, _, st)
  return unpack(M.read(st).vertexColor or M.WHITE, 1, #M.WHITE)
end

local function colorOf(value)
  return { value.r, value.g, value.b, value.a or DEFAULT_ALPHA }
end

-- source: W11, api/*/SimpleTextureBaseAPI.lua: `SetGradient(orientation, minColor, maxColor)` with colour objects on
-- every flavor. The separate-number form is not client behaviour, so a call without two colour tables changes nothing.
local function setGradient(_, _, st, orientation, minColor, maxColor)
  if type(minColor) ~= "table" or type(maxColor) ~= "table" then
    return
  end
  write(st).gradient = { orientation = orientation, min = colorOf(minColor), max = colorOf(maxColor) }
end

-- Flags --------------------------------------------------------------------------------------------------------

local function asFlag(value)
  return value and true or false
end

local function asIs(value)
  return value
end

local function setField(field, convert)
  return function(_, _, st, value)
    write(st)[field] = convert(value)
  end
end

local function getField(field, default)
  return function(_, _, st)
    local value = M.read(st)[field]
    if value == nil then
      return default
    end

    return value
  end
end

-- Masks --------------------------------------------------------------------------------------------------------

local function maskIndex(masks, mask)
  for i, item in ipairs(masks) do
    if item == mask then
      return i
    end
  end

  return nil
end

-- source: assumed (W15) AddMaskTexture is idempotent and masks are only counted, never drawn.
local function addMaskTexture(_, _, st, mask)
  local state = write(st)
  state.masks = state.masks or {}
  if not maskIndex(state.masks, mask) then
    state.masks[#state.masks + 1] = mask
  end
end

local function removeMaskTexture(_, _, st, mask)
  local masks = M.read(st).masks or {}
  local index = maskIndex(masks, mask)
  if index then
    table.remove(masks, index)
  end
end

local function getNumMaskTextures(_, _, st)
  return #(M.read(st).masks or {})
end

local TEXTURE_BASE_METHODS = {
  SetTexture = setTexture,
  GetTexture = getField("file", nil),
  SetColorTexture = setColorTexture,
  SetAtlas = setAtlas,
  GetAtlas = getField("atlas", nil),
  SetTexCoord = setTexCoord,
  GetTexCoord = getTexCoord,
  SetVertexColor = setVertexColor,
  GetVertexColor = getVertexColor,
  SetGradient = setGradient,
  -- source: W7, xsd:632 (Texture `alphaMode` default BLEND); W8 xsd:648, W9 xsd:635, W10 xsd:644-645.
  SetBlendMode = setField("blend", asIs),
  GetBlendMode = getField("blend", M.DEFAULT_BLEND),
  SetDesaturated = setField("desaturated", asFlag),
  IsDesaturated = getField("desaturated", false),
  SetRotation = setField("rotation", asIs),
  GetRotation = getField("rotation", 0),
  SetHorizTile = setField("horizTile", asFlag),
  GetHorizTile = getField("horizTile", false),
  SetVertTile = setField("vertTile", asFlag),
  GetVertTile = getField("vertTile", false),
}
for name, impl in pairs(TEXTURE_BASE_METHODS) do
  Typed.add(name, "texturebase", impl)
end

Typed.add("AddMaskTexture", "texture", addMaskTexture)
Typed.add("RemoveMaskTexture", "texture", removeMaskTexture)
Typed.add("GetNumMaskTextures", "texture", getNumMaskTextures)

-- Regions ------------------------------------------------------------------------------------------------------

-- source: W14, wiki API_Region_SetDrawLayer, sublevel "Integer between -8 and 7 (inclusive)", default 0; that an
-- out-of-range value clamps is assumed.
function methods.SetDrawLayer(_, _, st, layer, sublevel)
  local clamped = math.max(MIN_SUBLEVEL, math.min(MAX_SUBLEVEL, sublevel or DEFAULT_SUBLEVEL))
  st.values.DrawLayer = { n = 2, layer, clamped }
end

-- source: W13, xsd:640-641 (`ignoreParentAlpha`, `ignoreParentScale` default false); where the alpha and scale products
-- stop is assumed (ui/behaviour_render.lua).
function methods.SetIgnoreParentAlpha(_, _, st, ignore)
  st.ignoreAlpha = asFlag(ignore)
end

function methods.IsIgnoringParentAlpha(_, _, st)
  return st.ignoreAlpha or false
end

function methods.SetIgnoreParentScale(_, _, st, ignore)
  st.ignoreScale = asFlag(ignore)
end

function methods.IsIgnoringParentScale(_, _, st)
  return st.ignoreScale or false
end

return M
