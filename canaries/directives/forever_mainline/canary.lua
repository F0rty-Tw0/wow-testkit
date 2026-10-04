-- directives layer: WoW: Forever loads [AllowLoadGameType mainline] files, not [AllowLoadGameType standard] ones.
local dir = ...
local Support = require("canaries.support")

local function missing()
  if not rawget(_G, "CanaryForeverFile") then
    return { "file missing on forever" }
  end
  return {}
end

return {
  name = "forever_mainline",
  layer = "directives",
  flavors = { "forever" },
  knownMiss = false,
  check = function(variant, flavor)
    local _, findings = Support.login(dir, "CanaryForever", variant, flavor, missing)
    return findings
  end,
}
