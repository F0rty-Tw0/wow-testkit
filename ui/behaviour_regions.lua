-- Hand-written region creation: Frame:CreateTexture and Frame:CreateFontString store the draw layer the region was
-- created in, so GetDrawLayer answers. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local methods = {}
M.methods = methods

local DEFAULT_LAYER = "ARTWORK"
local DEFAULT_SUBLEVEL = 0

-- Creates a typeName region under obj and stores its DrawLayer pack. source: row V8 for CreateFontString's layer and
-- CreateTexture's sublevel (wiki API:Frame_CreateFontString `drawLayer` default ARTWORK, API:Frame_CreateTexture
-- `subLevel` default 0); CreateTexture's layer default ARTWORK is assumed (the page states none).
local function createRegion(w, obj, typeName, name, drawLayer, subLevel)
  local region = w.ui.create(typeName, name, obj)
  w.ui.state[region].values.DrawLayer = { n = 2, drawLayer or DEFAULT_LAYER, subLevel or DEFAULT_SUBLEVEL }
  return region
end

function methods.CreateTexture(w, obj, _, name, drawLayer, _, subLevel)
  return createRegion(w, obj, "Texture", name, drawLayer, subLevel)
end

-- A FontString has no sublevel (row V6): the client takes no subLevel argument, so it starts at 0.
function methods.CreateFontString(w, obj, _, name, drawLayer)
  return createRegion(w, obj, "FontString", name, drawLayer, nil)
end

return M
