-- directives layer: a mainline-only file loads on vanilla unless its TOC line has [AllowLoadGameType mainline].
local dir = ...
local Support = require("canaries.support")

local function loaded()
  if rawget(_G, "CanaryMainlineOnly") then
    return { "mainline-only file loaded on vanilla" }
  end
  return {}
end

return {
  name = "mainline_only",
  layer = "directives",
  flavors = { "vanilla" },
  knownMiss = false,
  check = function(variant, flavor)
    local _, findings = Support.login(dir, "CanaryMainline", variant, flavor, loaded)
    return findings
  end,
}
