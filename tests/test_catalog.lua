-- Compatibility catalog (catalog.lua): the user's addon list, the smoke run of the listed addons that exist in an addons
-- folder (never written to), the JSON document, the page step and `tk catalog` argument parsing.
local A = require("assert")
local B = require("tests.helpers.blizzard")
local Catalog = require("catalog")
local Json = require("json")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local DATE = "2026-10-24"

-- A temp addons folder: Good loads cleanly, Bad and Extra raise, NeedsBar raises unless the layer made MiniBar.
local function corpus()
  local dir = Tmp.dir("cat")
  local addons = {
    Good = "GoodLoaded = true\n",
    Bad = 'error("bad")\n',
    Extra = 'error("extra")\n',
    NeedsBar = 'if not MiniBar then error("no MiniBar") end\n',
  }
  for name, lua in pairs(addons) do
    fs.mkdirp(dir .. "/" .. name)
    fs.writeFile(dir .. "/" .. name .. "/" .. name .. ".toc", "## Interface: 120100\nMain.lua\n")
    fs.writeFile(dir .. "/" .. name .. "/Main.lua", lua)
  end
  return dir
end

local DIR = corpus()

-- Every file under dir (relative path -> contents), recursively.
local function listing(dir, prefix, out)
  out = out or {}
  for _, name in ipairs(fs.list(dir)) do
    local path, rel = dir .. "/" .. name, (prefix or "") .. name
    if fs.isdir(path) then
      listing(path, rel .. "/", out)
    else
      out[rel] = fs.readFile(path)
    end
  end
  return out
end

local function collector()
  local out = {}
  return function(text)
    out[#out + 1] = text
  end, function()
    return table.concat(out)
  end
end

-- Writes over.list to a temp list file, runs Catalog.run on DIR (retail only) into a temp out and returns the decoded
-- document, the exit code and the output.
local function runCatalog(over)
  local tmp = Tmp.dir("catrun")
  local opts = { dir = DIR, list = tmp .. "/addons.txt", out = tmp .. "/latest.json", flavors = { "retail" }, date = DATE }
  fs.writeFile(opts.list, over.list)
  for key, value in pairs(over) do
    if key ~= "list" then
      opts[key] = value
    end
  end
  local write, output = collector()
  local code = Catalog.run(opts, write)
  local text = fs.readFile(opts.out)
  return text and Json.decode(text), code, output()
end

local function runOf(doc, name)
  for _, addon in ipairs(doc.smoke.addons) do
    if addon.name == name then
      return addon.runs.retail
    end
  end
  return nil
end

local function test_read_list_skips_blanks_comments_and_duplicates()
  A.same(Catalog.readList("# mine\r\nGood\n\n  Bad  \nGood\n"), { "Good", "Bad" })
  A.same(Catalog.readList(""), {})
end

local function test_only_listed_addons_run_and_missing_ones_are_named()
  local doc, code, out = runCatalog({ list = "Good\nBad\nGone\n" })
  A.eq(code, 0)
  A.same({ doc.ver, doc.kind, doc.date }, { 1, "catalog", DATE })
  A.same(doc.listed, { "Good", "Bad", "Gone" })
  A.same(doc.missing, { "Gone" })
  A.eq(doc.smoke.totals.addons, 2) -- Extra is unlisted; it never ran
  A.same({ runOf(doc, "Good").status, runOf(doc, "Bad").status }, { "pass", "fail" })
  A.contains(runOf(doc, "Bad").errors[1].message, "bad")
  A.contains(out, "catalog: 3 listed, 1 missing, wrote ")
end

local function test_blizzard_ui_flag_is_recorded_and_reaches_the_run()
  local ex = B.extract(Tmp.dir("catbz"), B.mini())
  local off = runCatalog({ list = "NeedsBar\n" })
  local on = runCatalog({
    list = "NeedsBar\n",
    blizzardUi = { targets = { "Blizzard_MiniBar" } },
    findClient = function()
      return ex
    end,
  })
  A.same({ off.blizzardUi, on.blizzardUi }, { false, true })
  A.same({ runOf(off, "NeedsBar").status, runOf(on, "NeedsBar").status }, { "fail", "pass" })
end

-- Without an extract the layer loads nothing, so the document must not claim it ran.
local function test_blizzard_ui_without_an_extract_is_recorded_off()
  local doc = runCatalog({
    list = "Good\n",
    blizzardUi = true,
    findClient = function()
      return nil
    end,
  })
  A.eq(doc.blizzardUi, false)
end

local function test_unwritable_out_exits_1()
  local _, code, out = runCatalog({ list = "Good\n", out = Tmp.dir("catro") })
  A.eq(code, 1)
  A.contains(out, "catalog: could not write ")
  A.truthy(not out:find("wrote", 1, true), "no wrote line for a failed write")
end

local function test_catalog_never_writes_under_the_addons_dir()
  local before = listing(DIR)
  runCatalog({ list = "Good\nBad\nNeedsBar\n" })
  A.same(listing(DIR), before)
end

local function test_missing_or_empty_list_is_a_usage_error()
  local missing = Tmp.dir("catmiss") .. "/none.txt"
  local write, output = collector()
  A.eq(Catalog.run({ dir = DIR, list = missing }, write), 2)
  A.contains(output(), missing)
  local _, code, out = runCatalog({ list = "# only a comment\n\n" })
  A.eq(code, 2)
  A.contains(out, "addons.txt")
  local write2, output2 = collector()
  A.eq(Catalog.run({ dir = DIR .. "/nope", list = missing }, write2), 2)
  A.contains(output2(), "no such directory")
end

local function test_html_step_runs_the_page_tool()
  local calls = {}
  local real = Catalog.exec
  Catalog.exec = function(argv)
    calls[#calls + 1] = argv
    return 0
  end
  local tmp = Tmp.dir("cathtml")
  local ran, _, code, out = pcall(runCatalog, { list = "Good\n", out = tmp .. "/latest.json", html = tmp .. "/page.html" })
  Catalog.exec = real
  A.same({ ran, code }, { true, 0 })
  A.eq(calls[1][#calls[1] - 1], tmp .. "/latest.json") -- ..., "tools/catalog_page.py", <json>, <html>
  A.eq(calls[1][#calls[1]], tmp .. "/page.html")
  A.contains(calls[1][#calls[1] - 2], "tools/catalog_page.py")
  A.contains(out, "catalog: wrote " .. tmp .. "/page.html")
end

local function test_failed_page_tool_exits_1()
  local real = Catalog.exec
  Catalog.exec = function()
    return 3
  end
  local tmp = Tmp.dir("cathtml")
  local ran, _, code, out = pcall(runCatalog, { list = "Good\n", html = tmp .. "/page.html" })
  Catalog.exec = real
  A.same({ ran, code }, { true, 1 })
  A.contains(out, "catalog: page failed")
end

-- Catalog.main's parsed options, with Catalog.run stubbed.
local function mainOpts(argv)
  local seen
  local real = Catalog.run
  Catalog.run = function(opts)
    seen = opts
    return 0
  end
  local write, output = collector()
  local code = Catalog.main(argv, write)
  Catalog.run = real
  return seen, code, output()
end

local function test_main_parses_flavors_and_flags()
  local opts = mainOpts({ "dir\\", "retail", "mists", "retail", "--list", "l.txt", "--out", "o.json", "--html", "p.html", "--blizzard-ui" })
  A.same(opts, { dir = "dir", flavors = { "retail", "mists" }, list = "l.txt", out = "o.json", html = "p.html", blizzardUi = true })
  A.same(mainOpts({ "dir" }), { dir = "dir" })
end

local function test_main_usage_errors_exit_2()
  for _, argv in ipairs({ {}, { "dir", "pandaria" }, { "dir", "--list" }, { "dir", "--frob" } }) do
    local opts, code, out = mainOpts(argv)
    A.same({ opts, code }, { nil, 2 }, table.concat(argv, " "))
    A.contains(out, "usage: tk catalog")
  end
end

return function()
  test_read_list_skips_blanks_comments_and_duplicates()
  test_only_listed_addons_run_and_missing_ones_are_named()
  test_blizzard_ui_flag_is_recorded_and_reaches_the_run()
  test_blizzard_ui_without_an_extract_is_recorded_off()
  test_unwritable_out_exits_1()
  test_catalog_never_writes_under_the_addons_dir()
  test_missing_or_empty_list_is_a_usage_error()
  test_html_step_runs_the_page_tool()
  test_failed_page_tool_exits_1()
  test_main_parses_flavors_and_flags()
  test_main_usage_errors_exit_2()
end
