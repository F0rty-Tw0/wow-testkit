-- tk CLI: `tk test [flavor...] [--update] [--addon <path>]` runs an addon's scenarios and prints a summary;
-- `tk smoke <dir> [flavor...]` prints the smoke scoreboard for a folder of addons.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")
local Cli = require("bin.tk")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local HOVER_FIXTURE = TEST_DIR .. "/fixtures/addons/Hover"
local GOLDEN = "/tests/scenarios/golden/hover/tooltip.retail.txt"

local function tempDir(name)
  return Tmp.dir("cli") .. "/" .. name
end

local function copyTree(from, to)
  fs.mkdirp(to)
  for _, name in ipairs(fs.list(from)) do
    if fs.isdir(from .. "/" .. name) then
      copyTree(from .. "/" .. name, to .. "/" .. name)
    else
      fs.writeFile(to .. "/" .. name, assert(fs.readFile(from .. "/" .. name)))
    end
  end
end

-- A temp copy of the Hover fixture, so goldens never land in the repo.
local function hoverCopy()
  local root = tempDir("Hover")
  copyTree(HOVER_FIXTURE, root)
  return root
end

-- Runs Cli.main(argv); returns the exit code and the collected output.
local function run(argv)
  local out = {}
  local code = Cli.main(argv, function(text)
    out[#out + 1] = text
  end)
  return code, table.concat(out)
end

-- hoverCopy with every flavor's golden already written by an --update run.
local function acceptedHoverCopy()
  local root = hoverCopy()
  run({ "test", "--update", "--addon", root })
  return root
end

local function test_test_command_passes_the_hover_scenario()
  local code, out = run({ "test", "--addon", acceptedHoverCopy() })
  A.contains(out, "PASS hover retail")
  A.contains(out, "PASS hover vanilla")
  A.eq(code, 0)
end

local function test_missing_golden_fails_until_update_writes_it()
  local root = hoverCopy()
  local code, first = run({ "test", "retail", "--addon", root })
  A.contains(first, "FAIL hover retail: golden " .. root .. GOLDEN .. " is missing")
  A.contains(first, "rerun with --update to write it")
  A.eq(fs.exists(root .. GOLDEN), false)
  A.eq(code, 1)
  local _, accepted = run({ "test", "retail", "--update", "--addon", root })
  A.contains(accepted, "1 golden written")
  A.truthy(fs.exists(root .. GOLDEN), "golden written under the addon root")
  local again, second = run({ "test", "retail", "--addon", root })
  A.contains(second, "0 goldens written")
  A.eq(again, 0)
end

local function test_golden_mismatch_fails_first_with_the_diff()
  local root = acceptedHoverCopy()
  fs.writeFile(root .. GOLDEN, "L: [ffffff]Nope\n")
  local code, out = run({ "test", "retail", "--addon", root })
  A.eq(out:sub(1, #"FAIL hover retail: "), "FAIL hover retail: ")
  A.contains(out, "line 1")
  A.eq(code, 1)
end

local function test_update_rewrites_a_differing_golden()
  local root = acceptedHoverCopy()
  local accepted = fs.readFile(root .. GOLDEN)
  fs.writeFile(root .. GOLDEN, "L: [ffffff]Nope\n")
  local code = run({ "test", "retail", "--update", "--addon", root })
  A.eq(code, 0)
  A.eq(fs.readFile(root .. GOLDEN), accepted)
end

local function test_flavor_filter_runs_only_that_flavor()
  local code, out = run({ "test", "retail", "--addon", acceptedHoverCopy() })
  A.contains(out, "PASS hover retail")
  A.eq(out:find("vanilla", 1, true), nil)
  A.eq(code, 0)
end

local function test_scenario_file_that_cannot_run_fails()
  local root = acceptedHoverCopy()
  fs.writeFile(root .. "/tests/scenarios/scn_broken.lua", "return 42\n")
  local code, out = run({ "test", "retail", "--addon", root })
  A.contains(out, "FAIL broken -: ")
  A.contains(out, "PASS hover retail")
  A.eq(code, 1)
end

local function test_all_skipped_run_warns_and_exits_1()
  local root = tempDir("RetailOnly")
  copyTree(TEST_DIR .. "/fixtures/addons/RetailOnly", root)
  fs.mkdirp(root .. "/tests/scenarios")
  fs.writeFile(root .. "/tests/scenarios/scn_login.lua", "return { run = function(s) s:login() end }\n")
  local code, out = run({ "test", "vanilla", "tbc", "--addon", root })
  A.contains(out, "SKIP login vanilla (not declared)")
  A.contains(out, "nothing passed or failed")
  A.eq(code, 1)
end

local function test_unknown_command_exits_2()
  local code, out = run({ "frobnicate" })
  A.contains(out, "usage")
  A.eq(code, 2)
end

local function test_addon_without_scenarios_exits_2()
  local root = tempDir("Empty")
  fs.mkdirp(root)
  fs.writeFile(root .. "/Empty.toc", "## Interface: 120100\n")
  local code, out = run({ "test", "--addon", root })
  A.contains(out, "no scenarios")
  A.eq(code, 2)
end

local function test_dispatches_smoke()
  local code, out = run({ "smoke", TEST_DIR .. "/fixtures/smoke", "retail" })
  A.contains(out, "\nGood          PASS (0u)\n")
  A.eq(code, 0)
end

local function test_smoke_duplicate_flavor_runs_once()
  local code, out = run({ "smoke", TEST_DIR .. "/fixtures/smoke", "retail", "retail" })
  A.contains(out, "\n13 addons, 13 runs: 3 pass, 10 fail, 0 skipped\n")
  A.eq(code, 0)
end

local function test_smoke_unknown_flavor_exits_2()
  local code, out = run({ "smoke", TEST_DIR .. "/fixtures/smoke", "pandaria" })
  A.contains(out, "usage")
  A.eq(code, 2)
end

local function test_smoke_without_dir_exits_2()
  local code, out = run({ "smoke" })
  A.contains(out, "usage")
  A.eq(code, 2)
end

return function()
  test_test_command_passes_the_hover_scenario()
  test_missing_golden_fails_until_update_writes_it()
  test_golden_mismatch_fails_first_with_the_diff()
  test_update_rewrites_a_differing_golden()
  test_flavor_filter_runs_only_that_flavor()
  test_scenario_file_that_cannot_run_fails()
  test_all_skipped_run_warns_and_exits_1()
  test_unknown_command_exits_2()
  test_addon_without_scenarios_exits_2()
  test_dispatches_smoke()
  test_smoke_duplicate_flavor_runs_once()
  test_smoke_unknown_flavor_exits_2()
  test_smoke_without_dir_exits_2()
end
