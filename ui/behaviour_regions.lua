-- Hand-written region creation: Frame:CreateTexture and Frame:CreateFontString store the draw layer the region was
-- created in, so GetDrawLayer answers, and CreateFontString applies a font object template. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
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

function methods.CreateTexture(w, obj, _, name, drawLayer, _, subLevel)
  return createRegion(w, obj, "Texture", name, drawLayer, subLevel)
end

-- A template name is an XML virtual template (w.ui.virtuals) or a font object (a global Font): the font string takes the
-- font's font, size and flags as SetFontObject would. Any other name adds nothing and is counted in
-- w.unscripted["template:<Name>"], as CreateFrame counts an unknown template.
function M.applyFontTemplates(w, fontString, templates)
  if type(templates) ~= "string" then
    return
  end
  for name in templates:gmatch("[^,%s]+") do
    local virtual = w.ui.virtuals[name]
    local font = rawget(_G, name)
    local st = type(font) == "table" and w.ui.state[font]
    if virtual then
      virtual.apply(w, fontString, w.ui.state[fontString])
    elseif st and st.plan.isA.font then
      fontString:SetFontObject(font)
    else
      WorldApi.markUnscripted(w, "template:" .. name)
    end
  end
end

-- A FontString has no sublevel (row V6): the client takes no subLevel argument, so it starts at 0.
function methods.CreateFontString(w, obj, _, name, drawLayer, template)
  local fontString = createRegion(w, obj, "FontString", name, drawLayer, nil)
  M.applyFontTemplates(w, fontString, template)
  return fontString
end

return M
