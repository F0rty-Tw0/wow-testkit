-- AC6 probe: the CPU cost of one `sim step` call on a walking player. Usage (python tools/run51.py --script):
-- perf_probe.lua <addon-dir> <extract-dir|->
-- With an extract the session loads Blizzard's UI as well. Prints `sim step median=<ms> p95=<ms> blizzardUi=<bool>`.
-- os.clock ticks in whole milliseconds, so 300 steps are too fast to time one by one: the probe runs ROUNDS x 300
-- steps in timed batches of BATCH and each sample is a batch's mean per step; the p95 is of those means (the WASM page
-- times single steps).
local addonDir, extractArg = ...
local Session = require("session")
local Tmp = require("tests.helpers.tmp")

local STEPS = 300
local ROUNDS = 10
local BATCH = 100
local DT = 0.033
local print = print

local function percentile(sorted, fraction)
  return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function sample(sess)
  local request = { action = "step", seconds = DT }
  local samples = {}
  for i = 1, STEPS * ROUNDS / BATCH do
    local start = os.clock()
    for _ = 1, BATCH do
      local reply = sess:call("sim", request)
      assert(reply.ok, reply.error)
    end
    samples[i] = (os.clock() - start) * 1000 / BATCH
  end
  table.sort(samples)

  return samples
end

local extract = extractArg ~= "-" and extractArg or nil
local sess = Session.new({
  addonDir = addonDir,
  flavor = "retail",
  sessionDir = Tmp.dir("perf"),
  sim = {},
  extract = extract,
  blizzardUi = extract ~= nil,
})
local ok, result = pcall(function()
  assert(sess:call("input", { kind = "keydown", key = "W" }).ok)

  return sample(sess)
end)
sess:shutdown()
if not ok then
  error(result, 0)
end
print(string.format("sim step median=%.3f p95=%.3f blizzardUi=%s", percentile(result, 0.5), percentile(result, 0.95), tostring(extract ~= nil)))

return 0
