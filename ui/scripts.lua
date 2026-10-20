-- Script handlers per widget type and flavor, from Ketho's WidgetAPI `handlers` lists (inherited through the
-- type's ancestors). Retail's GameTooltip, for example, has no OnTooltipSetUnit; the Classic flavors do.
local M = {}

local Inherits = require("ui.inherits")
local Manifest = require("manifest")

local cache = {}

local function handlerSet(flavor, typeName)
  local _, globals = Manifest.load(flavor)
  local set = {}
  for _, ancestor in ipairs(Inherits.ancestors(globals.widgets, typeName)) do
    for _, handler in ipairs(globals.widgets[ancestor].handlers or {}) do
      set[handler] = true
    end
  end
  return set
end

-- True when a typeName widget accepts the script handler on flavor.
function M.supports(typeName, script, flavor)
  local key = flavor .. "\0" .. typeName
  local set = cache[key]
  if not set then
    set = handlerSet(flavor, typeName)
    cache[key] = set
  end
  return set[script] == true
end

return M
