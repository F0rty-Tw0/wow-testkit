-- P1: kit load. Per run, a fresh Scenario.new + s:login of one addon on retail, timed with os.clock.
-- Usage (python tools/run51.py --script): bench_load.lua <addonDir> [runs] [layer]
--   P1a SessionDemo, P1b any other addon, P1c with `layer` (the Blizzard UI layer, needs the retail client extract)
--   <id>       Scenario.new + login CPU ms
--   <id>.load  the sum of w.dev.loads[i].loadMs of the same run (addon.lua), ms
local Bench = require("tests.bench.bench")
local Scenario = require("scenario")
local Toc = require("toc")

local addonDir, runsText, layer = ...
local runs = Bench.runs(runsText)
local runtime = Bench.runtime()
local name = assert(Toc.addonName(addonDir))
local id = (layer == "layer" and "P1c") or (name == "SessionDemo" and "P1a") or "P1b"
local loads = {}

local function loadOnce()
  local s = Scenario.new({
    addon = name,
    root = addonDir,
    flavor = "retail",
    silencePrint = true,
    blizzardUi = layer == "layer" or nil,
  })
  local ok, err = pcall(s.login, s)
  local sum = 0
  for _, load in ipairs(s.w.dev.loads) do
    sum = sum + load.loadMs
  end
  s.w:destroy()
  if not ok then
    error(err, 0)
  end

  return sum
end

local samples = {}
for i = 1, runs do
  local start = os.clock()
  loads[i] = loadOnce()
  samples[i] = (os.clock() - start) * 1000
end
Bench.raw(id, runtime, samples)
Bench.raw(id .. ".load", runtime, loads)

return 0
