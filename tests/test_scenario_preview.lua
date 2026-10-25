-- s:preview writes numbered render snapshots under the output directory tk preview gives the scenario.
local A = require("assert")
local Scenario = require("scenario")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local HOVER = { addon = "Hover", root = TEST_DIR .. "/fixtures/addons/Hover" }

-- A Scenario on the Hover addon (never logged in), with preview output under out when given; always destroyed.
local function withScenario(out, fn)
  local preview = out and { out = out } or nil
  local s = Scenario.new({ addon = HOVER.addon, root = HOVER.root, flavor = "retail", preview = preview })
  local ok, err = pcall(fn, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function test_preview_writes_numbered_dirs_with_the_addons_map()
  local out = Tmp.dir("scnpreview")
  withScenario(out, function(s)
    s:login()
    s:preview("start")
    s:advance(1)
    s:preview("later_2-x")
  end)
  local first = assert(fs.readFile(out .. "/1-start/snapshot.json"))
  A.contains(first, '"ver": 1')
  A.contains(first, '"addons"')
  A.contains(first, '"Hover": "' .. HOVER.root .. '"')
  A.truthy(fs.exists(out .. "/2-later_2-x/snapshot.json"), "second preview in its own numbered dir")
end

local function test_preview_records_the_dirs_in_order()
  local out = Tmp.dir("scnpreview")
  withScenario(out, function(s)
    s:preview("a")
    s:preview("b")
    A.same(s.previews, { out .. "/1-a", out .. "/2-b" })
  end)
end

local function test_preview_rejects_a_name_with_other_characters()
  withScenario(Tmp.dir("scnpreview"), function(s)
    A.errors(function()
      s:preview("a b")
    end, "s:preview: name must be letters, digits, '_' or '-'")
    A.errors(function()
      s:preview("../x")
    end, "s:preview: name must be letters, digits, '_' or '-'")
  end)
end

-- %w matches the bytes of a locale's letters (here \233, e-acute in Latin-1/1252), so the name check must use ASCII
-- classes; a byte of a UTF-8 letter is rejected whatever the locale. Locales the machine lacks are skipped, and then
-- this only pins that the byte is rejected.
local LOCALES = { "", "French_France.1252", "fr_FR.ISO-8859-1", "en_US.ISO-8859-1" }

local function inLatinLocale(fn)
  local saved = os.setlocale()
  for _, name in ipairs(LOCALES) do
    if os.setlocale(name) and ("\233"):match("%w") then
      break
    end
  end
  local ok, err = pcall(fn)
  os.setlocale(saved)
  if not ok then
    error(err, 0)
  end
end

local function test_preview_rejects_a_byte_that_a_locale_calls_a_letter()
  withScenario(Tmp.dir("scnpreview"), function(s)
    inLatinLocale(function()
      for _, name in ipairs({ "caf\233", "caf\195\169", "\178" }) do
        A.errors(function()
          s:preview(name)
        end, "s:preview: name must be letters, digits, '_' or '-'")
      end
    end)
  end)
end

local function test_preview_without_an_output_directory_raises()
  withScenario(nil, function(s)
    A.errors(function()
      s:preview("start")
    end, "s:preview needs an output directory; run through tk preview")
  end)
end

return function()
  test_preview_writes_numbered_dirs_with_the_addons_map()
  test_preview_records_the_dirs_in_order()
  test_preview_rejects_a_name_with_other_characters()
  test_preview_rejects_a_byte_that_a_locale_calls_a_letter()
  test_preview_without_an_output_directory_raises()
end
