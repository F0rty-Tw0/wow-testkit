-- AC6 probe: the CPU cost of one `sim step` call on a walking player. Usage (python tools/run51.py --script):
-- perf_probe.lua <addon-dir> <extract-dir|->
-- With an extract the session loads Blizzard's UI as well. Prints `sim step median=<ms> p95=<ms> blizzardUi=<bool>` for the
-- walking player alone, then `sim step pack=<n> chasing median=<ms> p95=<ms> blizzardUi=<bool>` on a fresh session with a
-- pack of mobs six yards behind the player that chases it on every frame while it walks (the slice-3 worst case: each mob
-- steps, so each plate follows). The pack run is short, PACK_STEPS steps, so the pack is still chasing when it ends.
-- os.clock ticks in whole milliseconds, so 300 steps are too fast to time one by one: the probe runs ROUNDS x 300
-- steps in timed batches of BATCH and each sample is a batch's mean per step; the p95 is of those means (the WASM page
-- times single steps).
local addonDir, extractArg = ...
local Session = require("session")
local Tmp = require("tests.helpers.tmp")

local PACK = 10
local PACK_AT = { x = 0, y = -16 } -- six yards behind the player's spawn, inside the aggro radius
local PACK_STEPS = 200
local PACK_BATCH = 25
local STEPS = 300
local ROUNDS = 10
local BATCH = 100
local DT = 0.033
local print = print

local function percentile(sorted, fraction)
  return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function sample(sess, steps, batch)
  local request = { action = "step", seconds = DT }
  local samples = {}
  for i = 1, steps / batch do
    local start = os.clock()
    for _ = 1, batch do
      local reply = sess:call("sim", request)
      assert(reply.ok, reply.error)
    end
    samples[i] = (os.clock() - start) * 1000 / batch
  end
  table.sort(samples)

  return samples
end

local extract = extractArg ~= "-" and extractArg or nil

-- Median and p95 of a walking player's steps on a fresh session; beforeSteps(sess) may add to the world first and
-- afterSteps(sess) checks it was the world the run meant to time.
local function measure(steps, batch, beforeSteps, afterSteps)
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
    if beforeSteps then
      beforeSteps(sess)
    end

    local samples = sample(sess, steps, batch)
    if afterSteps then
      afterSteps(sess)
    end

    return samples
  end)
  sess:shutdown()
  if not ok then
    error(result, 0)
  end

  return percentile(result, 0.5), percentile(result, 0.95)
end

local function spawnPack(sess)
  local spawned = sess:call("sim", { action = "spawn", pack = PACK, pos = PACK_AT })
  assert(spawned.ok, spawned.error)
end

local function assertPackChases(sess)
  local engaged = 0
  for _, actor in pairs(sess.w.combat.actors) do
    engaged = engaged + (actor.mobState == "engaged" and 1 or 0)
  end
  assert(engaged == PACK, "the pack never engaged: " .. engaged .. " of " .. PACK)
end

local ui = tostring(extract ~= nil)
local median, p95 = measure(STEPS * ROUNDS, BATCH)
print(string.format("sim step median=%.3f p95=%.3f blizzardUi=%s", median, p95, ui))
median, p95 = measure(PACK_STEPS, PACK_BATCH, spawnPack, assertPackChases)
print(string.format("sim step pack=%d chasing median=%.3f p95=%.3f blizzardUi=%s", PACK, median, p95, ui))

return 0
