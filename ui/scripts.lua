-- Script handlers per widget type and flavor, from Ketho's WidgetAPI `handlers` lists (inherited through the
-- type's ancestors). Retail's GameTooltip, for example, has no OnTooltipSetUnit; the Classic flavors do.
local M = {}

local Inherits = require("ui.inherits")
local Manifest = require("manifest")

local cache = {}

-- { set = { [handler] = true }, byLower = { [lowercased handler] = handler } } of a typeName widget on flavor.
local function handlerSets(flavor, typeName)
  local key = flavor .. "\0" .. typeName
  local entry = cache[key]
  if not entry then
    local _, globals = Manifest.load(flavor)
    entry = { set = {}, byLower = {} }
    for _, ancestor in ipairs(Inherits.ancestors(globals.widgets, typeName)) do
      for _, handler in ipairs(globals.widgets[ancestor].handlers or {}) do
        entry.set[handler] = true
        entry.byLower[handler:lower()] = handler
      end
    end
    cache[key] = entry
  end
  return entry
end

-- True when a typeName widget accepts the script handler on flavor.
function M.supports(typeName, script, flavor)
  return handlerSets(flavor, typeName).set[script] == true
end

-- The handler name a typeName widget accepts on flavor that `script` spells in any case ("onload" gives "OnLoad"), or
-- nil.
function M.canonical(typeName, script, flavor)
  return handlerSets(flavor, typeName).byLower[script:lower()]
end

return M
