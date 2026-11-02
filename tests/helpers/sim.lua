-- Sim test helper: a Scenario world with the sim installed, run on one flavor or on all five. Tests never read a client
-- extract or install.
local Scenario = require("scenario")

local M = {}

M.FLAVORS = { "retail", "forever", "mists", "tbc", "vanilla" }

-- Runs fn(w, s) on a fresh Scenario world with the sim installed (simOpts defaults to {}); the world is always
-- destroyed.
function M.withSim(flavor, simOpts, fn)
  local s = Scenario.new({ addon = "T", root = "T", flavor = flavor, sim = simOpts or {} })
  local ok, err = pcall(fn, s.w, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

-- Runs fn(w, s, flavor) on every flavor in M.FLAVORS.
function M.each(simOpts, fn)
  for _, flavor in ipairs(M.FLAVORS) do
    M.withSim(flavor, simOpts, function(w, s)
      fn(w, s, flavor)
    end)
  end
end

-- Asserts |a - b| < 1e-6; the failure names the caller's line.
function M.near(a, b, msg)
  if type(a) ~= "number" or type(b) ~= "number" or math.abs(a - b) >= 1e-6 then
    error(string.format("%sexpected %s to be near %s", msg and (msg .. ": ") or "", tostring(a), tostring(b)), 2)
  end
end

-- The event names of a list of { event, ... } records, in order.
function M.names(log)
  local names = {}
  for i, record in ipairs(log) do
    names[i] = record[1]
  end

  return names
end

return M
