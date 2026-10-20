-- Minimap fakes: MinimapCluster and Minimap on every flavor.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local FLAVORS = { "retail", "mists", "vanilla", "tbc", "forever" }

local function test_minimap_is_child_of_cluster_on_every_flavor()
  for _, flavor in ipairs(FLAVORS) do
    HF.withFrameXML(flavor, function()
      A.eq(_G.Minimap:GetParent(), _G.MinimapCluster, flavor)
      A.same({ _G.Minimap:GetSize() }, { 140, 140 }, flavor)
    end)
  end
end

return function()
  test_minimap_is_child_of_cluster_on_every_flavor()
end
