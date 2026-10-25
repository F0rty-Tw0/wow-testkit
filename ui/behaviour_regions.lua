-- Hand-written region creation: Frame:CreateTexture and Frame:CreateFontString store the draw layer the region was
-- created in, so GetDrawLayer answers, and apply their template list. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local WorldApi = require("world_api")

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

-- A template name is an XML virtual template (w.ui.virtuals) or, for a font string, a font object (a global Font): the
-- font string takes the font's font, size and flags as SetFontObject would. Any other name adds nothing and is counted
-- in w.unscripted["template:<Name>"], as CreateFrame counts an unknown template.
function M.applyTemplates(w, region, templates)
  if type(templates) ~= "string" then
    return
  end
  local isFontString = w.ui.state[region].plan.isA.fontstring
  for name in templates:gmatch("[^,%s]+") do
    local virtual = w.ui.virtuals[name]
    local font = isFontString and rawget(_G, name)
    local st = type(font) == "table" and w.ui.state[font]
    if virtual then
      virtual.apply(w, region, w.ui.state[region])
    elseif st and st.plan.isA.font then
      region:SetFontObject(font)
    else
      WorldApi.markUnscripted(w, "template:" .. name)
    end
  end
end

-- CreateTexture's arguments are (name, drawLayer, template, subLevel).
function methods.CreateTexture(w, obj, _, name, drawLayer, template, subLevel)
  local texture = createRegion(w, obj, "Texture", name, drawLayer, subLevel)
  M.applyTemplates(w, texture, template)
  return texture
end

-- A FontString has no sublevel (row V6): the client takes no subLevel argument, so it starts at 0.
function methods.CreateFontString(w, obj, _, name, drawLayer, template)
  local fontString = createRegion(w, obj, "FontString", name, drawLayer, nil)
  M.applyTemplates(w, fontString, template)
  return fontString
end

return M
