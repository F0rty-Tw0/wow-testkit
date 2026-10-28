-- Compatibility catalog: `tk catalog <addons-dir> [flavor...] [--list FILE] [--out FILE] [--html FILE] [--blizzard-ui]`
-- runs the addons the user lists (a local file they curate; the kit ships and fetches none) that exist in an addons
-- folder through the smoke scenario, writes one JSON document and, with --html, a self-contained page of it
-- (tools/catalog_page.py). The addons folder is only read.
local M = {}

local Flavors = require("tools.flavors")
local Home = require("home")
local Json = require("json")
local Proc = require("proc")
local ScenarioBlizzard = require("scenario_blizzard")
local Smoke = require("smoke")
local SmokeJson = require("smoke_json")
local fs = require("fs")

local VERSION = 1
local INDENT = 2
local EXIT_OK, EXIT_FAIL, EXIT_USAGE = 0, 1, 2
local PAGE_LOG = "catalog-page.log"
-- Every kit module loads from the same package.path root as this file.
local KIT_ROOT = debug.getinfo(1, "S").source:match("^@(.*)[/\\]catalog%.lua$") or "."

M.USAGE = "usage: tk catalog <addons-dir> [flavor...] [--list FILE] [--out FILE] [--html FILE] [--blizzard-ui]\n"

-- Runs argv, logging its output to logPath; returns its exit code. Tests replace this field.
M.exec = Proc.run

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The addon folder names of a list file's text: one per line, trimmed; blank lines and # comments skipped; the first
-- occurrence of a name kept.
function M.readList(text)
  local names, seen = {}, {}
  for line in text:gmatch("[^\r\n]+") do
    local name = trim(line)
    local wanted = name ~= "" and name:sub(1, 1) ~= "#" and not seen[name]
    if wanted then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  return names
end

local function parentOf(path)
  return path:match("^(.*)/[^/]*$") or "."
end

-- Runs the page tool on the document at out; returns the exit code (1 when it fails), having said why.
local function writePage(out, html, write)
  local log = parentOf(out) .. "/" .. PAGE_LOG
  local argv = { Proc.python(), KIT_ROOT .. "/tools/catalog_page.py", out, html }
  local ran, code = pcall(M.exec, argv, log)
  if ran and code == 0 then
    write("catalog: wrote " .. html .. "\n")
    return EXIT_OK
  end
  local why = ran and "exit " .. tostring(code) or tostring(code)
  write("catalog: page failed (" .. why .. "): " .. (fs.readFile(log) or "") .. "\n")
  return EXIT_FAIL
end

-- The listed names, or nil plus the usage message naming the list path.
local function listedNames(path)
  local text = fs.readFile(path)
  if not text then
    return nil, "catalog: no addon list at " .. path .. "; write one addon folder name per line"
  end
  local names = M.readList(text)
  if #names == 0 then
    return nil, "catalog: the addon list " .. path .. " names no addon"
  end
  return names
end

-- Whether the Blizzard UI layer had an extract to load from on any of flavors (else it loaded nothing).
local function layerRan(opts, flavors)
  for _, flavor in ipairs(flavors) do
    local found = ScenarioBlizzard.client({ blizzardUi = opts.blizzardUi, findClient = opts.findClient, flavor = flavor })
    if found then
      return true
    end
  end
  return false
end

-- opts: { dir, list?, flavors?, blizzardUi?, findClient?, out?, html?, date? }. Runs Smoke.runAddon for each listed name
-- that is a folder of dir, writes out (default <home>/catalog/latest.json): { ver, kind = "catalog", date, blizzardUi
-- (the layer was asked for and found an extract), listed, missing, smoke = SmokeJson.document } and, with html, the
-- page. Returns 0 when it ran, 1 when out could not be written or the page step failed, 2 for a missing dir or a
-- missing or empty list.
function M.run(opts, write)
  local dir = opts.dir
  if not (dir and fs.isdir(dir)) then
    write("catalog: no such directory: " .. tostring(dir) .. "\n")
    return EXIT_USAGE
  end
  local listPath = opts.list or Home.path("catalog", "addons.txt")
  local listed, err = listedNames(listPath)
  if not listed then
    write(err .. "\n")
    return EXIT_USAGE
  end
  local flavors = opts.flavors or Flavors.list
  local extra = { blizzardUi = opts.blizzardUi, findClient = opts.findClient }
  local results, missing = {}, {}
  for _, name in ipairs(listed) do
    local root = dir .. "/" .. name
    if fs.isdir(root) then
      results[#results + 1] = Smoke.runAddon(root, flavors, nil, extra)
    else
      missing[#missing + 1] = name
    end
  end
  local document = {
    ver = VERSION,
    kind = "catalog",
    date = opts.date or os.date("%Y-%m-%d"),
    blizzardUi = layerRan(opts, flavors),
    listed = listed,
    missing = missing,
    smoke = SmokeJson.document(results, flavors),
  }
  local out = opts.out or Home.path("catalog", "latest.json")
  fs.mkdirp(parentOf(out))
  local wrote, writeErr = pcall(fs.writeFile, out, Json.encode(document, INDENT) .. "\n")
  if not wrote then
    write("catalog: could not write " .. out .. ": " .. tostring(writeErr) .. "\n")
    return EXIT_FAIL
  end
  write(string.format("catalog: %d listed, %d missing, wrote %s\n", #listed, #missing, out))
  if opts.html then
    return writePage(out, opts.html, write)
  end
  return EXIT_OK
end

local OPTION_FIELDS = { ["--list"] = "list", ["--out"] = "out", ["--html"] = "html" }

-- Catalog.run opts from argv (after the verb), or nil plus a message. A repeated flavor runs once, in first-seen order.
local function parse(argv)
  if not argv[1] or argv[1]:sub(1, 2) == "--" then
    return nil, "catalog needs an addons directory"
  end
  local opts, flavors, seen, i = { dir = argv[1]:gsub("\\", "/"):gsub("(.)/+$", "%1") }, {}, {}, 2
  while i <= #argv do
    local arg, field = argv[i], OPTION_FIELDS[argv[i]]
    if field then
      i = i + 1
      opts[field] = argv[i]
      if not opts[field] then
        return nil, arg .. " needs a path"
      end
    elseif arg == "--blizzard-ui" then
      opts.blizzardUi = true
    elseif not pcall(Flavors.get, arg) then
      return nil, "unknown flavor or option '" .. arg .. "'; flavors: " .. table.concat(Flavors.list, ", ")
    elseif not seen[arg] then
      seen[arg] = true
      flavors[#flavors + 1] = arg
    end
    i = i + 1
  end
  opts.flavors = #flavors > 0 and flavors or nil
  return opts
end

-- `tk catalog` with argv after the verb; all output goes through write. Returns the exit code.
function M.main(argv, write)
  local opts, err = parse(argv)
  if not opts then
    write(err .. "\n" .. M.USAGE)
    return EXIT_USAGE
  end
  return M.run(opts, write)
end

return M
