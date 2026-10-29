-- P7: the known hotspots of the sandbox-gaps plan (2026-10-24-sandbox-gaps.md:489-491).
-- Usage (python tools/run51.py --script): bench_known.lua taint|log|call|advance [runs]
--   taint    P7a  500 SetPoint calls from addon code on a protected frame in combat, 1500 frames in the world (a fresh
--                 world per run; taint_frames.lua M.isProtected scans every widget per call)
--   log      P7b  Render.snapshot with 1000 taint-log entries (render.lua copyLog, taint.lua LOG_LIMIT)
--   call     P7c  ms for 10000 no-op w:callAsAddon calls (divide by 10 for microseconds per call)
--   advance  P7d  s:advance(3600) under the Blizzard UI layer (needs the retail client extract; a fresh world per run)
local Bench = require("tests.bench.bench")
local Render = require("render")
local Scenario = require("scenario")
local Taint = require("tests.helpers.taint")

local which, runsText = ...
local runs = Bench.runs(runsText)
local runtime = Bench.runtime()

local FRAMES = 1500
local BLOCKED_CALLS = 500
local LOG_ENTRIES = 1000
local CALLS = 10000
local ADVANCE_SECONDS = 3600
local SESSION_DEMO = "tests/fixtures/addons/SessionDemo"
local BLOCKED_SRC = "for _ = 1, %d do TKBenchSec:SetPoint('TOPLEFT', 5, 5) end"

local function newWorld()
  return Scenario.new({ addon = "T", root = "T", flavor = "retail", silencePrint = true })
end

-- A world with FRAMES frames, one of them a protected button named TKBenchSec, in combat. Returns the scenario and a
-- chunk of addon "Foo" that makes `calls` refused SetPoint calls on it.
local function combatWorld(calls)
  local s = newWorld()
  _G.CreateFrame("Button", "TKBenchSec", _G.UIParent, "SecureActionButtonTemplate")
  for _ = 2, FRAMES do
    _G.CreateFrame("Frame")
  end
  Taint.setCombat(s.w, true)

  return s, Taint.chunk(s.w, "Foo", BLOCKED_SRC:format(calls))
end

local function refusedCalls(ctx)
  local results = ctx.w:callAsAddon(ctx.chunk)
  assert(results[1], "the refused calls raised")
  assert(#ctx.w.taint.log > 0, "the calls were not refused: the bench measures nothing")
end

local function benchTaint()
  local function build()
    local s, chunk = combatWorld(BLOCKED_CALLS)

    return { w = s.w, chunk = chunk }, function()
      s.w:destroy()
    end
  end
  Bench.fresh("P7a", runtime, runs, build, refusedCalls)
end

local function benchLog()
  local s, chunk = combatWorld(LOG_ENTRIES)
  local w = s.w
  local ok, err = pcall(function()
    refusedCalls({ w = w, chunk = chunk })
    assert(#w.taint.log == LOG_ENTRIES, "the log holds " .. #w.taint.log .. " entries, want " .. LOG_ENTRIES)
    Bench.measure("P7b", runtime, runs, function()
      Render.snapshot(w)
    end)
  end)
  w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function benchCall()
  local w = newWorld().w
  local noop = Taint.chunk(w, "Foo", "")
  local ok, err = pcall(Bench.measure, "P7c", runtime, runs, function()
    for _ = 1, CALLS do
      w:callAsAddon(noop)
    end
  end)
  w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function benchAdvance()
  local function build()
    local s = Scenario.new({ addon = "SessionDemo", root = SESSION_DEMO, flavor = "retail", silencePrint = true, blizzardUi = true })
    s:login()

    return s, function()
      s.w:destroy()
    end
  end
  Bench.fresh("P7d", runtime, runs, build, function(s)
    s:advance(ADVANCE_SECONDS)
  end)
end

local BENCHES = { taint = benchTaint, log = benchLog, call = benchCall, advance = benchAdvance }
local run = BENCHES[which]
if not run then
  error("usage: bench_known.lua taint|log|call|advance [runs]", 0)
end
run()

return 0
