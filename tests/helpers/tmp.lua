-- Unique temp directory paths for tests. Seeding with os.time() alone gave two suites started in the same second
-- the same names, so the seed also mixes in CPU time and this process's heap address, and a taken name is skipped.
local fs = require("fs")

local M = {}

local function seed()
  local address = tonumber(tostring({}):match("(%x+)$"), 16) or 0
  math.randomseed((os.time() + math.floor(os.clock() * 1000000) + address) % 2147483647)
end

seed()

-- A path under the temp folder named wow-testkit-<prefix>-<random>-<random> that does not exist yet.
function M.dir(prefix)
  local base = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/")
  local path
  repeat
    path = string.format("%s/wow-testkit-%s-%d-%d", base, prefix, math.random(1, 1000000), math.random(1, 1000000))
  until not fs.exists(path)
  return path
end

return M
