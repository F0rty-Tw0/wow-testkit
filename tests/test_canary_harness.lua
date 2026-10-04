local A = require("assert")
local Harness = require("canaries.run")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local CANARIES_DIR = TEST_DIR .. "/../canaries"

local function canary(findings, fields)
  local c = {
    name = "c",
    layer = "l",
    flavors = { "retail" },
    check = function(variant)
      return findings[variant]
    end,
  }
  for k, v in pairs(fields or {}) do
    c[k] = v
  end
  return c
end

local function test_unflagged_bug_fails()
  local results = Harness.evaluate(canary({ bug = {}, fixed = {} }))
  A.eq(results[1].pass, false)
  A.eq(results[1].reason, "bug not flagged")
end

local function test_flagged_fixed_fails_with_first_finding()
  local results = Harness.evaluate(canary({ bug = { "b" }, fixed = { "false positive", "y" } }))
  A.eq(results[1].pass, false)
  A.eq(results[1].reason, "fixed flagged: false positive")
end

local function test_flagged_known_miss_fails()
  local results = Harness.evaluate(canary({ bug = { "x" }, fixed = {} }, { knownMiss = true }))
  A.eq(results[1].pass, false)
  A.contains(results[1].reason, "known-miss now flagged")
end

local function test_unflagged_known_miss_passes()
  local results = Harness.evaluate(canary({ bug = {}, fixed = {} }, { knownMiss = true }))
  A.eq(results[1].pass, true)
end

local function test_good_canary_passes_for_each_flavor()
  local results = Harness.evaluate(canary({ bug = { "b" }, fixed = {} }, { flavors = { "retail", "vanilla" } }))
  A.same(results, {
    { name = "c", layer = "l", flavor = "retail", pass = true },
    { name = "c", layer = "l", flavor = "vanilla", pass = true },
  })
end

local function test_nil_flavors_evaluates_retail_once()
  local c = canary({ bug = { "b" }, fixed = {} })
  c.flavors = nil
  local results = Harness.evaluate(c)
  A.eq(#results, 1)
  A.eq(results[1].flavor, "retail")
end

local function test_check_error_fails_with_message()
  local results = Harness.evaluate(canary({}, {
    check = function()
      error("boom", 0)
    end,
  }))
  A.eq(results[1].pass, false)
  A.eq(results[1].reason, "check errored: boom")
end

local function test_discover_loads_synthetic_basic_with_its_dir()
  local found = Harness.discover(CANARIES_DIR)
  A.eq(found[1].layer, "_synthetic")
  A.eq(found[1].name, "basic")
  A.same(found[1].check("bug", "retail"), { "synthetic bug" })
end

return function()
  test_unflagged_bug_fails()
  test_flagged_fixed_fails_with_first_finding()
  test_flagged_known_miss_fails()
  test_unflagged_known_miss_passes()
  test_good_canary_passes_for_each_flavor()
  test_nil_flavors_evaluates_retail_once()
  test_check_error_fails_with_message()
  test_discover_loads_synthetic_basic_with_its_dir()
end
