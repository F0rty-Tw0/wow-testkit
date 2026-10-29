-- Smoke runaway guard with the Blizzard UI layer on (ruling R-debt-1): the budget counts addon-owned execution only, so
-- the layer's own login work is free while an addon's work still counts, also when Blizzard code calls the addon.
local TEST_BUDGET = 100000
local BUDGET_MESSAGE = "smoke: instruction budget exceeded"
local LAYER_MESSAGE = "smoke: Blizzard UI layer instruction budget exceeded"

local A = require("assert")
local B = require("tests.helpers.blizzard")
local Smoke = require("smoke")
local Tmp = require("tests.helpers.tmp")

-- A layer file: on PLAYER_LOGIN it sums 1..50000 and makes 100 securecallfunction calls (each past TEST_BUDGET, both
-- inside the layer's; the API reaches the kit through tail calls, as Blizzard's CallbackRegistry and Pools calls do),
-- then calls every MiniCallbacks entry and MiniRun, the way EventUtil.ContinueAfterAllEvents and a hooked Blizzard
-- function hand control to addon code.
local LOGIN_WORK = [[
MiniCallbacks = {}
function MiniRun() end
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  local sum = 0
  for i = 1, 50000 do sum = sum + i end
  MiniLoginSum = sum
  local noop = function() end
  for _ = 1, 100 do securecallfunction(noop) end
  for _, callback in ipairs(MiniCallbacks) do callback() end
  MiniRun()
  if MiniSpin then
    for i = 1, MiniSpin do sum = sum + i end
    MiniSpinDone = true
  end
end)
]]

local function runProbe(lua)
  local toc = "## Interface: 120100\nMiniBase.lua\nLogin.lua\n"
  local addons = B.mini({ blizzard_minibase = { toc = toc, files = { ["login.lua"] = LOGIN_WORK } } })
  local extract = B.extract(Tmp.dir("smokelayer"), addons)
  local extra = { blizzardUi = { targets = { "Blizzard_MiniBase" } }, client = extract }
  local report = Smoke.runAddon(B.probe(lua), { "retail" }, TEST_BUDGET, extra).results.retail
  A.eq(debug.gethook(), nil)
  return report
end

-- About 2M instructions of addon code: past TEST_BUDGET, but inside the layer's budget while the loop tests raise
-- LAYER_FACTOR, so the run fails only when the work is charged to the addon (charged to the layer, it passes).
local ADDON_WORK = "function() local sum = 0 for i = 1, 500000 do sum = sum + i end end"

-- Runs probe lua with Smoke.LAYER_FACTOR raised so the layer's budget cannot be what trips, and checks the trip.
local function assertAddonTrips(lua)
  local factor = Smoke.LAYER_FACTOR
  Smoke.LAYER_FACTOR = 1000
  local ok, report = pcall(runProbe, lua)
  Smoke.LAYER_FACTOR = factor
  assert(ok, report)
  A.eq(report.status, "fail")
  A.contains(report.errors[1].message, BUDGET_MESSAGE)
end

local function test_heavy_layer_login_work_does_not_count()
  -- PLAYER_ENTERING_WORLD follows PLAYER_LOGIN, so the probe sees whether the layer's work ran to the end.
  local lua = 'local f = CreateFrame("Frame")\nf:RegisterEvent("PLAYER_ENTERING_WORLD")\n'
    .. 'f:SetScript("OnEvent", function() if MiniLoginSum ~= 1250025000 then error("layer work cut short") end end)\n'
  local report = runProbe(lua)
  A.eq(report.status, "pass", report.errors[1] and tostring(report.errors[1].message))
end

local function test_addon_work_in_its_login_handler_still_counts()
  assertAddonTrips('local f = CreateFrame("Frame")\nf:RegisterEvent("PLAYER_LOGIN")\nf:SetScript("OnEvent", ' .. ADDON_WORK .. ")\n")
end

local function test_addon_work_in_a_callback_blizzard_calls_still_counts()
  assertAddonTrips("MiniCallbacks[#MiniCallbacks + 1] = " .. ADDON_WORK .. "\n")
end

local function test_addon_work_in_a_hook_of_a_blizzard_function_still_counts()
  assertAddonTrips('hooksecurefunc("MiniRun", ' .. ADDON_WORK .. ")\n")
end

-- The layer's own backstop: a layer loop past TEST_BUDGET * LAYER_FACTOR is cut short, so a Blizzard loop the kit sends
-- into a spin still ends. The probe sets MiniSpin to about 4M instructions of layer work, past the layer's 1M. The
-- trip names the layer: the probe's next handler dies with the layer's message, not the addon budget's.
local function test_layer_work_past_the_layer_budget_is_cut_short()
  local lua = 'MiniSpin = 1000000\nlocal f = CreateFrame("Frame")\nf:RegisterEvent("PLAYER_ENTERING_WORLD")\n'
    .. 'f:SetScript("OnEvent", function() if MiniSpinDone then error("layer spin ran to the end") end end)\n'
  local report = runProbe(lua)
  A.eq(report.status, "fail")
  A.contains(report.errors[1].message, LAYER_MESSAGE)
  for _, e in ipairs(report.errors) do
    A.eq(tostring(e.message):find("layer spin ran to the end", 1, true), nil)
  end
end

-- The budget is per run: coroutines charge the same counter. One coroutine of about 60k addon instructions fits in
-- TEST_BUDGET; three of them do not, where a fresh budget per coroutine would let them pass.
local function test_addon_coroutines_share_one_budget()
  local function work(count)
    local loop = "for _ = 1, %d do coroutine.wrap(function() local sum = 0 for i = 1, 30000 do sum = sum + i end end)() end\n"
    return loop:format(count)
  end
  local one = runProbe(work(1))
  A.eq(one.status, "pass", one.errors[1] and tostring(one.errors[1].message))
  assertAddonTrips(work(3))
end

return function()
  test_layer_work_past_the_layer_budget_is_cut_short()
  test_addon_coroutines_share_one_budget()
  test_heavy_layer_login_work_does_not_count()
  test_addon_work_in_its_login_handler_still_counts()
  test_addon_work_in_a_callback_blizzard_calls_still_counts()
  test_addon_work_in_a_hook_of_a_blizzard_function_still_counts()
end
