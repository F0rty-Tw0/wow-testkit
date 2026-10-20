-- Smoke scoreboard: addon folder discovery, the built-in scenario, the runaway guard and the scoreboard text.
local TEST_BUDGET = 100000

local A = require("assert")
local Flavors = require("tools.flavors")
local Smoke = require("smoke")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local SMOKE_DIR = TEST_DIR .. "/fixtures/smoke"

local function runFixture(name, flavors, budget)
  return Smoke.runAddon(SMOKE_DIR .. "/" .. name, flavors or Flavors.list, budget or TEST_BUDGET)
end

local function test_one_row_per_addon_folder()
  local folders = Smoke.addonFolders(SMOKE_DIR)
  A.same(folders, {
    "Bad",
    "Clobber",
    "CoLoop",
    "CoThenTicker",
    "CoTicker",
    "Good",
    "Loop",
    "LsTicker",
    "MainlineToc",
    "NoName",
    "RetailOnly",
    "Ticker",
    "WrapError",
  })
end

local function test_skips_blizzard_folders()
  A.truthy(fs.exists(SMOKE_DIR .. "/Blizzard_Fake/Blizzard_Fake.toc"), "Blizzard_Fake fixture is missing")
  for _, name in ipairs(Smoke.addonFolders(SMOKE_DIR)) do
    A.truthy(name ~= "Blizzard_Fake", "Blizzard_Fake was listed")
  end
end

local function test_pass_fail_skip_cells()
  local good, bad, retailOnly = runFixture("Good"), runFixture("Bad"), runFixture("RetailOnly")
  for _, flavor in ipairs(Flavors.list) do
    A.eq(good.results[flavor].status, "pass", "Good on " .. flavor)
    A.eq(bad.results[flavor].status, "fail", "Bad on " .. flavor)
    A.eq(#bad.results[flavor].errors, 1, "Bad errors on " .. flavor)
    A.eq(retailOnly.results[flavor].status, flavor == "retail" and "pass" or "skipped", "RetailOnly on " .. flavor)
  end
  A.eq(#retailOnly.results.vanilla.errors, 0, "RetailOnly errors on vanilla")
end

local function test_unnamed_folder_fails_each_flavor()
  local result = runFixture("NoName")
  A.eq(result.name, "NoName")
  for _, flavor in ipairs(Flavors.list) do
    local report = result.results[flavor]
    A.eq(report.status, "fail", flavor)
    A.eq(#report.errors, 1, flavor)
    A.contains(report.errors[1].message, "cannot tell which TOC")
  end
end

local BUDGET_MESSAGE = "smoke: instruction budget exceeded"

local function assertRunaway(report)
  A.eq(report.status, "fail")
  A.contains(report.errors[1].message, BUDGET_MESSAGE)
end

local function test_runaway_addon_fails_with_budget_message()
  assertRunaway(runFixture("Loop", { "retail" }).results.retail)
end

local function test_runaway_inside_coroutine_fails_with_budget_message()
  assertRunaway(runFixture("CoLoop", { "retail" }).results.retail)
end

-- The real budget on purpose: without tripped mode this run takes hours, so a regression shows as a CI timeout.
local function test_runaway_ticker_ends_run()
  local results = runFixture("Ticker", { "retail", "vanilla" }, Smoke.BUDGET).results
  assertRunaway(results.retail)
  A.eq(results.vanilla.status, "skipped")
end

-- A trip inside a coroutine must also cut the main thread's later runaway callbacks short.
local function test_runaway_after_coroutine_trip_ends_run()
  local results = runFixture("CoThenTicker", { "retail", "vanilla" }, Smoke.BUDGET).results
  assertRunaway(results.retail)
  A.eq(results.vanilla.status, "skipped")
end

local function test_runaway_ticker_in_coroutine_ends_run()
  assertRunaway(runFixture("CoTicker", { "retail" }, Smoke.BUDGET).results.retail)
end

local function test_runaway_loadstring_ticker_ends_run()
  assertRunaway(runFixture("LsTicker", { "retail" }, Smoke.BUDGET).results.retail)
end

local function test_guard_disarmed_after_skipped_and_failed_runs()
  runFixture("Loop", { "retail", "vanilla" })
  A.eq(debug.gethook(), nil)
  A.eq(runFixture("RetailOnly", { "vanilla" }).results.vanilla.status, "skipped")
end

local function test_guard_survives_addon_clobbering_coroutine()
  assertRunaway(runFixture("Clobber", { "retail" }).results.retail)
  A.eq(runFixture("Good", { "retail" }).results.retail.status, "pass")
end

-- The guard's coroutine.wrap must word errors like Lua's own: string errors gain the caller's position.
local function test_guarded_wrap_error_matches_plain_wrap()
  local path = SMOKE_DIR .. "/WrapError/WrapError.lua"
  local chunk = assert(loadstring(assert(fs.readFile(path)), "@addon:WrapError/WrapError.lua"))
  local _, plain = pcall(chunk)
  A.contains(plain, "WrapError.lua:5: wrapped")
  A.eq(runFixture("WrapError", { "retail" }).results.retail.errors[1].message, plain)
end

local function failed(firstMessage, unscripted)
  return { status = "fail", errors = { { message = firstMessage }, { message = "later" } }, unscripted = unscripted or {} }
end

local function passed(unscripted)
  return { status = "pass", errors = {}, unscripted = unscripted or {} }
end

local function unscriptedNames(...)
  local list = {}
  for i, name in ipairs({ ... }) do
    list[i] = { name = name, count = 7 }
  end
  return list
end

local function capture(fn)
  local out = {}
  local code = fn(function(text)
    out[#out + 1] = text
  end)
  return code, table.concat(out)
end

local function test_scoreboard_rows_pad_columns_and_trim()
  local skipped = { status = "skipped", errors = {}, unscripted = {} }
  local results = {
    { name = "Zed", results = { retail = passed(unscriptedNames("A", "B")), vanilla = skipped } },
    { name = "Alphabet", results = { retail = failed("x"), vanilla = passed() } },
  }
  local expected = "addon     retail       vanilla\n"
    .. "Alphabet  FAIL 2 (0u)  PASS (0u)\n"
    .. "Zed       PASS (2u)    SKIP\n"
    .. "first errors (runs):\n"
  local text = Smoke.format(results, { "retail", "vanilla" })
  A.eq(text:sub(1, #expected), expected)
end

local function test_unnamed_folder_row()
  local text = Smoke.format({ runFixture("NoName") }, Flavors.list)
  local row = text:match("\n(NoName[^\n]*)")
  local _, cells = row:gsub("FAIL 1", "")
  A.eq(cells, #Flavors.list)
end

local function test_groups_first_errors_with_tie_break()
  local results = {
    { name = "B", results = { retail = failed("b"), vanilla = failed("a") } },
    { name = "A", results = { retail = failed("x"), vanilla = failed("b") } },
    { name = "C", results = { retail = passed(), vanilla = failed("a") } },
  }
  for i = 1, 9 do
    results[#results + 1] = { name = "N" .. i, results = { retail = failed("c" .. i), vanilla = passed() } }
  end
  local text = Smoke.format(results, { "retail", "vanilla" })
  local expected = "first errors (runs):\n  2  a\n  2  b\n  1  c1\n  1  c2\n  1  c3\n  1  c4\n  1  c5\n  1  c6\n  1  c7\n  1  c8\n"
  A.contains(text, expected .. "unscripted (runs):\n")
end

local function test_ranks_unscripted_names_with_tie_break()
  local results = {
    { name = "A", results = { retail = passed(unscriptedNames("GetLocale", "Foo")), vanilla = failed("e", unscriptedNames("GetLocale")) } },
    { name = "B", results = { retail = passed(unscriptedNames("Foo", "Bar")), vanilla = passed() } },
  }
  A.contains(Smoke.format(results, { "retail", "vanilla" }), "unscripted (runs):\n  Foo x2, GetLocale x2, Bar x1\n")
end

local function test_totals_line()
  local code, text = capture(function(write)
    return Smoke.run({ dir = SMOKE_DIR, budget = TEST_BUDGET }, write)
  end)
  A.eq(code, 0)
  A.contains(text, "13 addons, 65 runs: 8 pass, 18 fail, 39 skipped\n")
end

local function test_missing_dir_exits_2()
  local code, text = capture(function(write)
    return Smoke.run({ dir = SMOKE_DIR .. "/Missing" }, write)
  end)
  A.eq(code, 2)
  A.contains(text, SMOKE_DIR .. "/Missing")
end

local function test_dir_without_addon_folders_exits_2()
  local code, text = capture(function(write)
    return Smoke.run({ dir = SMOKE_DIR .. "/Good" }, write)
  end)
  A.eq(code, 2)
  A.contains(text, "no addon folders")
end

return function()
  test_one_row_per_addon_folder()
  test_skips_blizzard_folders()
  test_pass_fail_skip_cells()
  test_unnamed_folder_fails_each_flavor()
  test_runaway_addon_fails_with_budget_message()
  test_runaway_inside_coroutine_fails_with_budget_message()
  test_runaway_ticker_ends_run()
  test_runaway_after_coroutine_trip_ends_run()
  test_runaway_ticker_in_coroutine_ends_run()
  test_runaway_loadstring_ticker_ends_run()
  test_guard_disarmed_after_skipped_and_failed_runs()
  test_guard_survives_addon_clobbering_coroutine()
  test_guarded_wrap_error_matches_plain_wrap()
  test_scoreboard_rows_pad_columns_and_trim()
  test_unnamed_folder_row()
  test_groups_first_errors_with_tie_break()
  test_ranks_unscripted_names_with_tie_break()
  test_totals_line()
  test_missing_dir_exits_2()
  test_dir_without_addon_folders_exits_2()
end
