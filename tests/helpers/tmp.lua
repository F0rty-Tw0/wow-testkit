-- Unique temp directories for tests. Seeding with os.time() alone gave two suites started in the same second the
-- same names, so the seed also mixes in CPU time and this process's heap address. Seeds can still match across
-- processes, so each directory is claimed with an atomic fs.mkdir and a taken name is skipped.
local fs = require("fs")

local M = {}

local function seed()
  local address = tonumber(tostring({}):match("(%x+)$"), 16) or 0
  math.randomseed((os.time() + math.floor(os.clock() * 1000000) + address) % 2147483647)
end

seed()

-- A new, empty directory under the temp folder named wow-testkit-<prefix>-<random>-<random>, created by this call.
function M.dir(prefix)
  local base = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/")
  local path
  repeat
    path = string.format("%s/wow-testkit-%s-%d-%d", base, prefix, math.random(1, 1000000), math.random(1, 1000000))
  until fs.mkdir(path)
  return path
end

return M
