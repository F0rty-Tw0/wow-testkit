-- loader layer: a module read before the file defining it falls back to require, which WoW: Forever rejects
-- with "Invalid import".
local dir = ...
local Support = require("canaries.support")

local INVALID_IMPORT = "Invalid import"

return {
  name = "require_fallback",
  layer = "loader",
  flavors = { "forever" },
  knownMiss = false,
  check = function(variant, flavor)
    return Support.errors((Support.login(dir, "CanaryOrder", variant, flavor)), INVALID_IMPORT)
  end,
}
