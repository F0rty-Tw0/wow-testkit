-- api layer: a retail-only function is not installed on vanilla, so an unguarded call errors there.
-- C_PlayerInfo.GetPlayerMythicPlusRatingSummary is absent from the vanilla manifest and globals tier.
local dir = ...
local Support = require("canaries.support")

return {
  name = "mplus_rating",
  layer = "api",
  flavors = { "vanilla" },
  knownMiss = false,
  check = function(variant, flavor)
    return Support.errors((Support.login(dir, "CanaryMPlus", variant, flavor)))
  end,
}
