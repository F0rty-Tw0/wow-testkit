-- templates layer: a CreateFrame template the kit does not know is counted as unscripted "template:<Name>".
local dir = ...
local Support = require("canaries.support")

return {
  name = "unknown_template",
  layer = "templates",
  flavors = { "retail" },
  knownMiss = false,
  check = function(variant, flavor)
    return Support.unscriptedTemplates((Support.login(dir, "CanaryTemplate", variant, flavor)))
  end,
}
