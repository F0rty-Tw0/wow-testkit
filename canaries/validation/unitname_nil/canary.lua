-- validation layer: an addon-context API call missing a required argument is a recorded error.
local dir = ...
local Support = require("canaries.support")

return {
  name = "unitname_nil",
  layer = "validation",
  flavors = { "retail" },
  knownMiss = false,
  check = function(variant, flavor)
    return Support.errors((Support.login(dir, "CanaryUnitName", variant, flavor)))
  end,
}
