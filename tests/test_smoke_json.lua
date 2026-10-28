-- Smoke JSON: the document tk smoke --json prints and the silenced, counted print of a smoke run.
local TEST_BUDGET = 100000

local A = require("assert")
local Json = require("json")
local Smoke = require("smoke")
local SmokeJson = require("smoke_json")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local EXPECTED = [[
{
  "addons": [
    {
      "name": "A",
      "runs": {
        "retail": {
          "errors": [],
          "printed": 0,
          "status": "pass",
          "unscripted": []
        },
        "vanilla": {
          "errors": [],
          "printed": 0,
          "reason": "no TOC for this flavor",
          "status": "skipped",
          "unscripted": []
        }
      }
    }
  ],
  "flavors": [
    "retail",
    "vanilla"
  ],
  "totals": {
    "addons": 1,
    "fail": 0,
    "pass": 1,
    "runs": 2,
    "skipped": 1
  },
  "ver": 1
}
]]
local function test_document_matches_the_schema()
  local results = {
    {
      name = "A",
      results = {
        retail = { status = "pass", errors = {}, unscripted = {} },
        vanilla = { status = "skipped", reason = "no TOC for this flavor", errors = {}, unscripted = {} },
      },
    },
  }
  A.textEq(SmokeJson.format(results, { "retail", "vanilla" }), EXPECTED)
end
local function test_failed_run_keeps_only_message_and_sorted_unscripted()
  local run = { status = "fail", errors = { { message = "boom", traceback = "tb" } }, unscripted = { { name = "A", count = 2 } }, printed = 3 }
  local text = SmokeJson.format({ { name = "B", results = { retail = run } } }, { "retail" })
  A.contains(text, '"errors": [\n            {\n              "message": "boom"\n            }\n          ]')
  A.contains(text, '"name": "A"')
  A.contains(text, '"printed": 3')
  A.eq(text:find("traceback", 1, true), nil)
end
local function test_addons_and_unscripted_names_are_sorted()
  local run = { status = "fail", errors = {}, unscripted = { { name = "Zed", count = 1 }, { name = "Alpha", count = 2 } } }
  local results = { { name = "Second", results = { retail = run } }, { name = "First", results = { retail = run } } }
  local text = SmokeJson.format(results, { "retail" })
  local first, second = text:find('"name": "First"', 1, true), text:find('"name": "Second"', 1, true)
  local alpha, zed = text:find('"name": "Alpha"', 1, true), text:find('"name": "Zed"', 1, true)
  A.same({ first < second, alpha < zed }, { true, true })
end
local function test_print_is_silenced_and_counted()
  local corpus = Tmp.dir("loud")
  fs.mkdirp(corpus .. "/Loud")
  fs.writeFile(corpus .. "/Loud/Loud.toc", "## Interface: 120100\nLoud.lua\n")
  fs.writeFile(corpus .. "/Loud/Loud.lua", 'print("noise")\n')
  local calls = 0
  local real = _G.print
  local spy = function()
    calls = calls + 1
  end
  _G.print = spy
  local result = Smoke.runAddon(corpus .. "/Loud", { "retail" }, TEST_BUDGET)
  local restored = _G.print
  _G.print = real
  A.same({ calls, result.results.retail.printed, result.results.retail.status }, { 0, 1, "pass" })
  A.eq(restored, spy) -- the world's destroy restores the spy, not the real print
end

local function test_document_is_the_table_format_encodes()
  local results = { { name = "A", results = { retail = { status = "fail", errors = { { message = "boom" } }, unscripted = {} } } } }
  local document = SmokeJson.document(results, { "retail" })
  A.same({ document.ver, document.totals.fail, document.addons[1].runs.retail.errors }, { 1, 1, { { message = "boom" } } })
  A.textEq(SmokeJson.format(results, { "retail" }), Json.encode(document, 2) .. "\n")
end

return function()
  test_document_matches_the_schema()
  test_document_is_the_table_format_encodes()
  test_failed_run_keeps_only_message_and_sorted_unscripted()
  test_addons_and_unscripted_names_are_sorted()
  test_print_is_silenced_and_counted()
end
