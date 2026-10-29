-- The singular RequiredDep directive (row BU9). Its own file: tests/test_toc.lua and toc.lua sit at the line limit.
local A = require("assert")
local Toc = require("toc")

-- source: assumed (row BU9) RequiredDep lists required addons as RequiredDeps does: 27 retail Blizzard TOCs write it, e.g.
-- blizzard_worldmap_mainline.toc "## RequiredDep: Blizzard_MapCanvas", and WorldMap.lua:130 needs MapCanvasMixin at load.
local function test_required_dep_lists_required_addons_assumed()
  local meta = Toc.parse("## RequiredDep: A, B\n## OptionalDeps: C\nX.lua\n").meta
  A.same(Toc.dependencies(meta), { required = { "A", "B" }, optional = { "C" } })
end

return function()
  test_required_dep_lists_required_addons_assumed()
end
