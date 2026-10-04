-- MinimapCluster and Minimap (a Minimap widget where the flavor's WidgetAPI has the type, else a Frame).
local M = {}

local Core = require("framexml.fakes.core")

local MINIMAP_SIZE = 140

function M.install(w)
  local cluster = Core.createNamed(w, "Frame", "MinimapCluster", _G.UIParent)
  local minimapType = w.globals.widgets.Minimap and "Minimap" or "Frame"
  local minimap = Core.createNamed(w, minimapType, "Minimap", cluster)
  if minimap then
    minimap:SetSize(MINIMAP_SIZE, MINIMAP_SIZE)
  end
end

return M
