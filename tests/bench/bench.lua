-- Bench helpers (plan 13-performance.md, Task 13.1). Every bench prints `RAW <id> <runtime> <ms> <ms> ...` with all its
-- samples; tests/bench/summarize.py turns RAW lines into BENCH lines, the only place a median is computed.
-- The runtime label comes from BENCH_RUNTIME (default lupa51: python tools/run51.py --script ...; CI's real Lua 5.1 is
-- lua51). os.clock is 1 ms resolution, so a sample under MIN_SAMPLE_MS loops the call until it is long enough.
local M = {}

-- Captured at load: a world silences the global print while it lives.
local print = print

local MIN_SAMPLE_MS = 20
local DEFAULT_RUNTIME = "lupa51"

function M.runtime()
  local label = os.getenv("BENCH_RUNTIME")

  return (label and label ~= "") and label or DEFAULT_RUNTIME
end

-- The runs count from the script's argument (default 5), or an error naming the bad value.
function M.runs(text)
  local count = text == nil and 5 or tonumber(text)
  if not count or count < 1 or count ~= math.floor(count) then
    error("runs must be a positive integer, got " .. tostring(text), 0)
  end

  return count
end

-- Prints the RAW line of samples (ms).
function M.raw(id, runtime, samples)
  local parts = {}
  for i, ms in ipairs(samples) do
    parts[i] = string.format("%.3f", ms)
  end
  print("RAW " .. id .. " " .. runtime .. " " .. table.concat(parts, " "))
end

-- ms of one call of fn, or, when that is under MIN_SAMPLE_MS, ms per call over k calls with k doubling until the
-- loop takes at least MIN_SAMPLE_MS.
local function sampleMs(fn)
  local calls = 1
  while true do
    local start = os.clock()
    for _ = 1, calls do
      fn()
    end
    local ms = (os.clock() - start) * 1000
    if ms >= MIN_SAMPLE_MS then
      return ms / calls
    end
    calls = calls * 2
  end
end

-- Prints `runs` samples of fn (ms per call) and returns them.
function M.measure(id, runtime, runs, fn)
  local samples = {}
  for i = 1, runs do
    samples[i] = sampleMs(fn)
  end
  M.raw(id, runtime, samples)

  return samples
end

-- Like measure, but each run builds its own context: build() (untimed) returns ctx and an optional cleanup; one call of
-- fn(ctx) is timed (use it when a call takes well over MIN_SAMPLE_MS or changes the state it measures).
function M.fresh(id, runtime, runs, build, fn)
  local samples = {}
  for i = 1, runs do
    local ctx, cleanup = build()
    collectgarbage() -- twice: the first pass only queues finalizers, and a GC step inside the timed call is an outlier
    collectgarbage()
    local start = os.clock()
    local ok, err = pcall(fn, ctx)
    samples[i] = (os.clock() - start) * 1000
    if cleanup then
      cleanup()
    end
    if not ok then
      error(err, 0)
    end
  end
  M.raw(id, runtime, samples)

  return samples
end

return M
