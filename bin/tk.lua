-- tk: the kit's command line.
--   require("bin.tk")                                       -> module (Cli.main)
--   python tools/run51.py --script bin/tk.lua test [...]    -> runs the command, returns its exit code
-- `tk test [flavor...] [--update] [--addon <path>]` runs <addon>/tests/scenarios/scn_*.lua on each flavor and
-- prints failures first, then one line per scenario and flavor, the most common unscripted calls and the totals.
-- `tk smoke <dir> [flavor...] [--json]` runs every addon folder in <dir> through the built-in smoke scenario and
-- prints one scoreboard, or with --json a diffable JSON document.
-- `tk preview <addon-dir> [--flavor F] [--scenario FILE] [--size WxH] [--out DIR] [--png FILE]` runs the addon, writes
-- the render snapshot to <out>/snapshot.json and, with --png, a Chrome screenshot of it.
-- `tk client extract|status [args]` extracts data from the installed game client or reports the extract's state
-- (client_cli.lua).
local ClientCli = require("client_cli")
local fs = require("fs")
local Flavors = require("tools.flavors")
local Preview = require("preview")
local Scenario = require("scenario")
local Smoke = require("smoke")
local Toc = require("toc")

local Cli = {}

local isModule = (...) == "bin.tk"

local USAGE = "usage: tk test [flavor...] [--update] [--addon <path>] | tk smoke <dir> [flavor...] [--json]"
  .. " | tk preview <addon-dir> [--flavor F] [--scenario FILE] [--size WxH] [--out DIR] [--png FILE]"
  .. " | tk client extract|status [args]\n"
local EXIT_OK, EXIT_FAIL, EXIT_USAGE = 0, 1, 2
local UNSCRIPTED_TOP = 10
local MAX_SIDE = 16384
local PREVIEW_PATH_FLAGS = { ["--scenario"] = "scenario", ["--out"] = "out", ["--png"] = "png" }
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

-- { dir, flavors?, json } from argv[2..], or nil plus a message. A repeated flavor runs once, in first-seen order.
local function parseSmoke(argv)
  local dir, flavors, seen, json = argv[2], {}, {}, false
  if not dir then
    return nil, "smoke needs a directory"
  end
  for i = 3, #argv do
    if argv[i] == "--json" then
      json = true
    elseif not pcall(Flavors.get, argv[i]) then
      return nil, "unknown flavor '" .. argv[i] .. "'; flavors: " .. table.concat(Flavors.list, ", ")
    elseif not seen[argv[i]] then
      seen[argv[i]] = true
      flavors[#flavors + 1] = argv[i]
    end
  end
  local cleaned = dir:gsub("\\", "/"):gsub("(.)/+$", "%1")
  return { dir = cleaned, flavors = #flavors > 0 and flavors or nil, json = json }
end

local function slashes(path)
  return (path:gsub("\\", "/"):gsub("(.)/+$", "%1"))
end

-- { width, height } from "WxH" (both in 1..MAX_SIDE), or nil.
local function parseSize(text)
  local width, height = text:match("^(%d+)x(%d+)$")
  width, height = tonumber(width), tonumber(height)
  if width and height and width >= 1 and height >= 1 and width <= MAX_SIDE and height <= MAX_SIDE then
    return { width = width, height = height }
  end
  return nil
end

-- Sets opts for one preview flag from value; returns an error message or nil.
local function setPreviewFlag(opts, flag, value)
  if flag == "--flavor" then
    if not pcall(Flavors.get, value) then
      return "unknown flavor '" .. value .. "'; flavors: " .. table.concat(Flavors.list, ", ")
    end
    opts.flavor = value
  elseif flag == "--size" then
    opts.size = parseSize(value)
    if not opts.size then
      return "--size needs WxH with both sides from 1 to " .. MAX_SIDE .. ", got '" .. value .. "'"
    end
  else
    opts[PREVIEW_PATH_FLAGS[flag]] = slashes(value)
  end
  return nil
end

-- { addonDir, flavor?, scenario?, size?, out?, png? } from argv[2..], or nil plus a message.
local function parsePreview(argv)
  local dir = argv[2]
  if not dir or dir:sub(1, 2) == "--" then
    return nil, "preview needs an addon directory"
  end
  local opts, i = { addonDir = slashes(dir) }, 3
  while i <= #argv do
    local flag = argv[i]
    if flag ~= "--flavor" and flag ~= "--size" and not PREVIEW_PATH_FLAGS[flag] then
      return nil, "unknown option '" .. flag .. "'"
    end
    i = i + 1
    if not argv[i] then
      return nil, flag .. " needs a value"
    end
    local err = setPreviewFlag(opts, flag, argv[i])
    if err then
      return nil, err
    end
    i = i + 1
  end
  return opts
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
    addon, err = Toc.addonName(opts.root)
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

local function smokeCommand(argv, write)
  local opts, err = parseSmoke(argv)
  if not opts then
    write(err .. "\n" .. USAGE)
    return EXIT_USAGE
  end
  return Smoke.run(opts, write)
end

local function previewCommand(argv, write)
  local opts, err = parsePreview(argv)
  if not opts then
    write(err .. "\n" .. USAGE)
    return EXIT_USAGE
  end
  return Preview.run(opts, write)
end

local function clientCommand(argv, write)
  return ClientCli.run({ unpack(argv, 2) }, write)
end

-- Runs argv (without the program name); all output goes through write. Returns the exit code.
function Cli.main(argv, write)
  if argv[1] == "test" then
    return testCommand(argv, write)
  elseif argv[1] == "smoke" then
    return smokeCommand(argv, write)
  elseif argv[1] == "preview" then
    return previewCommand(argv, write)
  elseif argv[1] == "client" then
    return clientCommand(argv, write)
  end
  write(USAGE)
  return EXIT_USAGE
end

if isModule then
  return Cli
end

return Cli.main({ ... }, io.write)
