-- Proves the canary harness only: each variant's check.lua returns its findings directly.
local dir = ...

return {
  name = "basic",
  layer = "_synthetic",
  knownMiss = false,
  check = function(variant)
    return assert(loadfile(dir .. "/" .. variant .. "/check.lua"))()
  end,
}
