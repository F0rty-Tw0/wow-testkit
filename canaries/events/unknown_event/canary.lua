-- events layer: registering an event the flavor does not have is a recorded error.
-- WEEKLY_REWARDS_UPDATE is absent from the vanilla manifest events and globals events.
local dir = ...
local Support = require("canaries.support")

return {
  name = "unknown_event",
  layer = "events",
  flavors = { "vanilla" },
  knownMiss = false,
  check = function(variant, flavor)
    return Support.errors((Support.login(dir, "CanaryEvent", variant, flavor)))
  end,
}
