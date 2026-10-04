-- tk: the kit's command line.
--   require("bin.tk")                                       -> module (Cli.main)
--   python tools/run51.py --script bin/tk.lua test [...]    -> runs the command, returns its exit code
-- `tk test [flavor...] [--update] [--addon <path>]` runs <addon>/tests/scenarios/scn_*.lua on each flavor and
-- prints failures first, then one line per scenario and flavor, the most common unscripted calls and the totals.
local fs = require("fs")
local Flavors = require("tools.flavors")
local Scenario = require("scenario")

local Cli = {}

local isModule = (...) == "bin.tk"

local USAGE = "usage: tk test [flavor...] [--update] [--addon <path>]\n"
local EXIT_OK, EXIT_FAIL, EXIT_USAGE = 0, 1, 2
local UNSCRIPTED_TOP = 10
local SCENARIO_DIR = "/tests/scenarios"
local SCENARIO_FILE = "^scn_(.+)%.lua$"
local GOLDEN_WRITTEN = "^golden written: "
local NOTHING_RAN = "WARNING: nothing passed or failed (every scenario was skipped); check the TOC and the flavor filter\n"

-- { flavors?, update?, root } from argv[2..], or nil plus a message.
local function parseTest(argv)
  local opts, flavors, i = {}, {}, 2
  while i <= #argv do
    local arg = argv[i]
    if arg == "--update" then
      opts.update = true
    elseif arg == "--addon" then
      i = i + 1
      opts.root = argv[i]
      if not opts.root then
        return nil, "--addon needs a path"
      end
    elseif pcall(Flavors.get, arg) then
      flavors[#flavors + 1] = arg
    else
      return nil, "unknown flavor or option '" .. arg .. "'; flavors: " .. table.concat(Flavors.list, ", ")
    end
    i = i + 1
  end
  opts.root = (opts.root or "."):gsub("\\", "/"):gsub("(.)/+$", "%1")
  opts.flavors = #flavors > 0 and flavors or nil
  return opts
end

-- The TOC base name with any flavor suffix (_Mainline, _Vanilla, ...) removed.
local function tocBase(file)
  local base = file:match("^(.+)%.toc$")
  for _, flavor in ipairs(Flavors.list) do
    for _, suffix in ipairs(Flavors.get(flavor).tocSuffixes) do
      if base and base:sub(-#suffix) == suffix then
        return base:sub(1, -#suffix - 1)
      end
    end
  end
  return base
end

-- The addon name: the TOC named after the root folder, else the only TOC base name there.
local function addonName(root)
  local names, seen = {}, {}
  for _, file in ipairs(fs.list(root)) do
    local base = tocBase(file)
    if base and not seen[base] then
      seen[base] = true
      names[#names + 1] = base
    end
  end
  local folder = (root == "." and os.getenv("PWD") or root):gsub("\\", "/"):match("([^/]+)/*$")
  if folder and seen[folder] then
    return folder
  elseif #names == 1 then
    return names[1]
  end
  return nil, "cannot tell which TOC is the addon's in " .. root .. " (found " .. #names .. " TOC names)"
end

local function scenarioPaths(root)
  local dir, paths = root .. SCENARIO_DIR, {}
  if fs.isdir(dir) then
    for _, file in ipairs(fs.list(dir)) do
      if file:match(SCENARIO_FILE) then
        paths[#paths + 1] = dir .. "/" .. file
      end
    end
  end
  table.sort(paths)
  return paths
end

local function failedRow(path, message)
  local report = { status = "fail", errors = { { message = message } }, unscripted = {}, notes = {} }
  return { scenario = path:match("([^/]+)$"):match(SCENARIO_FILE), flavor = "-", report = report }
end

-- One row per scenario and flavor, in Flavors.list order. A scenario file that cannot run is one failed row.
local function runScenarios(opts, addon, paths)
  local rows = {}
  for _, path in ipairs(paths) do
    local runOpts = { addon = addon, root = opts.root, flavors = opts.flavors, update = opts.update }
    local ok, result = pcall(Scenario.runFile, path, runOpts)
    if not ok then
      rows[#rows + 1] = failedRow(path, result)
    else
      for _, flavor in ipairs(Flavors.list) do
        if result.results[flavor] then
          rows[#rows + 1] = { scenario = result.name, flavor = flavor, report = result.results[flavor] }
        end
      end
    end
  end
  return rows
end

local function unscriptedLine(rows)
  local totals, list, parts = {}, {}, {}
  for _, row in ipairs(rows) do
    for _, item in ipairs(row.report.unscripted) do
      totals[item.name] = (totals[item.name] or 0) + item.count
    end
  end
  for name, count in pairs(totals) do
    list[#list + 1] = { name = name, count = count }
  end
  table.sort(list, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.name < b.name
  end)
  for i = 1, math.min(#list, UNSCRIPTED_TOP) do
    parts[i] = list[i].name .. " x" .. list[i].count
  end
  return "unscripted: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
end

local function rowLine(row)
  local id = row.scenario .. " " .. row.flavor
  local status = row.report.status
  if status == "pass" then
    return "PASS " .. id
  elseif status == "skipped" then
    return "SKIP " .. id .. " (" .. (row.report.reason or "skipped") .. ")"
  end
  return "FAIL " .. id
end

-- Prints the summary; returns the counts { pass, fail, skipped, written }.
local function report(rows, write)
  local counts = { pass = 0, fail = 0, skipped = 0, written = 0 }
  for _, row in ipairs(rows) do
    if row.report.status == "fail" then
      write("FAIL " .. row.scenario .. " " .. row.flavor .. ": " .. tostring(row.report.errors[1].message) .. "\n")
    end
  end
  for _, row in ipairs(rows) do
    write(rowLine(row) .. "\n")
    counts[row.report.status] = counts[row.report.status] + 1
    for _, note in ipairs(row.report.notes) do
      counts.written = counts.written + (note:find(GOLDEN_WRITTEN) and 1 or 0)
    end
  end
  write(unscriptedLine(rows) .. "\n")
  local goldens = counts.written == 1 and "golden" or "goldens"
  write(string.format("%d passed, %d failed, %d skipped, %d %s written\n", counts.pass, counts.fail, counts.skipped, counts.written, goldens))
  return counts
end

-- A run where nothing passed or failed proves nothing, so it fails with a warning.
local function exitCode(counts, write)
  if counts.fail > 0 then
    return EXIT_FAIL
  elseif counts.pass == 0 then
    write(NOTHING_RAN)
    return EXIT_FAIL
  end
  return EXIT_OK
end

local function testCommand(argv, write)
  local opts, err = parseTest(argv)
  local addon
  if opts then
    addon, err = addonName(opts.root)
  end
  if not addon then
    write(err .. "\n" .. USAGE)
    return EXIT_USAGE
  end
  local paths = scenarioPaths(opts.root)
  if #paths == 0 then
    write("no scenarios: " .. opts.root .. SCENARIO_DIR .. "/scn_*.lua\n")
    return EXIT_USAGE
  end
  return exitCode(report(runScenarios(opts, addon, paths), write), write)
end

-- Runs argv (without the program name); all output goes through write. Returns the exit code.
function Cli.main(argv, write)
  if argv[1] == "test" then
    return testCommand(argv, write)
  end
  write(USAGE)
  return EXIT_USAGE
end

if isModule then
  return Cli
end

return Cli.main({ ... }, io.write)
