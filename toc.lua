-- Addon TOC files: picks a flavor's TOC, parses its metadata and file lines, checks the declared interface
-- version, and lists the Lua files a flavor loads (game-type directives applied, XML Script/Include expanded).
local M = {}

local Flavors = require("tools.flavors")
local fs = require("fs")

local INTERFACE_KEY = "Interface"
local GAME_TYPE_DIRECTIVE = "AllowLoadGameType"
local UTF8_BOM = "^\239\187\191"

-- Every game type some flavor answers to; a game-type list naming none of them cannot exclude a file.
local KNOWN_GAME_TYPES = {}
for _, name in ipairs(Flavors.list) do
  for gameType in pairs(Flavors.get(name).gameTypes) do
    KNOWN_GAME_TYPES[gameType] = true
  end
end

local function trim(text)
  return (text:match("^%s*(.-)%s*$"))
end

-- Items separated by spaces and/or commas.
local function splitList(text)
  local out = {}
  for item in text:gmatch("[^,%s]+") do
    out[#out + 1] = item
  end
  return out
end

local function sortedKeys(set)
  local keys = {}
  for key in pairs(set) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

-- Path of the TOC the client reads for flavor: the first existing suffixed TOC, else <name>.toc.
function M.select(root, name, flavor)
  for _, suffix in ipairs(Flavors.get(flavor).tocSuffixes) do
    local path = root .. "/" .. name .. suffix .. ".toc"
    if fs.exists(path) then
      return path
    end
  end
  return root .. "/" .. name .. ".toc"
end

-- "Core\X.lua [AllowLoadGameType vanilla, tbc]" -> { path = "Core/X.lua", directives = { AllowLoadGameType = set } }
local function parseFileLine(line)
  local directives = {}
  while true do
    local before, body = line:match("^(.-)%s*%[([^%]]*)%]$")
    local name, args = (body or ""):match("^%s*(%S+)%s*(.-)%s*$")
    if not name or before == "" then
      break
    end
    local set = {}
    for _, arg in ipairs(splitList(args)) do
      set[arg:lower()] = true
    end
    directives[name] = set
    line = before
  end
  return { path = (line:gsub("\\", "/")), directives = directives }
end

function M.parse(text)
  local parsed = { meta = {}, files = {} }
  for raw in (text:gsub(UTF8_BOM, "")):gmatch("[^\r\n]+") do
    local line = trim(raw)
    local key, value = line:match("^##%s*(.-)%s*:%s*(.-)$")
    if key then
      parsed.meta[key] = value
    elseif line ~= "" and line:sub(1, 1) ~= "#" then
      parsed.files[#parsed.files + 1] = parseFileLine(line)
    end
  end
  parsed.savedVariables = splitList(parsed.meta.SavedVariables or "")
  parsed.savedVariablesPerCharacter = splitList(parsed.meta.SavedVariablesPerCharacter or "")
  return parsed
end

local function interfaceValues(meta, row)
  for _, key in ipairs(row.interfaceKeys) do
    if meta[key] then
      return meta[key]
    end
  end
  return meta[INTERFACE_KEY] or ""
end

-- "load" | "outdated" | "ahead" | "not-declared". Only values of the flavor's major.minor count; a higher patch
-- wins over a lower one (the TOC already covers the current patch).
function M.declared(meta, flavor)
  local row = Flavors.get(flavor)
  local lower, higher = false, false
  for _, item in ipairs(splitList(interfaceValues(meta, row))) do
    local version = tonumber(item)
    if version and Flavors.majorMinorOf(version) == row.majorMinor then
      if version == row.tocVersion then
        return "load"
      end
      lower = lower or version < row.tocVersion
      higher = higher or version > row.tocVersion
    end
  end
  if higher then
    return "ahead"
  end
  return lower and "outdated" or "not-declared"
end

local function reportIgnoredDirectives(file, report)
  for _, name in ipairs(sortedKeys(file.directives)) do
    if name ~= GAME_TYPE_DIRECTIVE then
      report[#report + 1] = file.path .. ": ignored directive [" .. name .. "]"
    end
  end
end

-- A game-type list loads the file when it shares a type with the flavor, or names no known type at all.
local function allowedOn(file, row, report)
  local gameTypes = file.directives[GAME_TYPE_DIRECTIVE]
  if not gameTypes then
    return true
  end
  local namesKnownType = false
  for name in pairs(gameTypes) do
    if row.gameTypes[name] then
      return true
    end
    namesKnownType = namesKnownType or KNOWN_GAME_TYPES[name] == true
  end
  if namesKnownType then
    return false
  end
  local names = table.concat(sortedKeys(gameTypes), ", ")
  report[#report + 1] = file.path .. ": [" .. GAME_TYPE_DIRECTIVE .. "] names no known game type (" .. names .. "); loaded"
  return true
end

local function join(dir, relative)
  relative = relative:gsub("\\", "/")
  return dir and (dir .. "/" .. relative) or relative
end

local function fileAttribute(attributes)
  return attributes:match('file%s*=%s*"([^"]*)"') or attributes:match("file%s*=%s*'([^']*)'")
end

local expandXml

-- One opening tag of an XML file: Script adds its file, Include recurses, Ui is a container; others are reported.
local function addTag(ctx, tag, attributes)
  local kind = tag:lower()
  local file = fileAttribute(attributes)
  if kind == "script" and file then
    ctx.files[#ctx.files + 1] = join(ctx.dir, file)
  elseif kind == "include" and file then
    expandXml(join(ctx.dir, file), ctx.readFile, ctx.files, ctx.report)
  elseif kind ~= "ui" and not ctx.seen[tag] then
    ctx.seen[tag] = true
    local what = (kind == "script" or kind == "include") and ("inline <" .. tag .. ">") or ("unsupported XML <" .. tag .. ">")
    ctx.report[#ctx.report + 1] = ctx.path .. ": " .. what .. " ignored"
  end
end

expandXml = function(path, readFile, files, report)
  local text = readFile(path)
  if not text then
    report[#report + 1] = path .. ": cannot read XML file"
    return
  end
  local ctx = { path = path, dir = path:match("^(.*)/[^/]*$"), readFile = readFile, files = files, report = report, seen = {} }
  for closing, tag, attributes in (text:gsub("<!%-%-.-%-%->", "")):gmatch("<(/?)([%w_:]+)(.-)/?>") do
    if closing == "" then
      addTag(ctx, tag, attributes)
    end
  end
end

local function addFile(path, readFile, files, report)
  local extension = (path:match("%.(%w+)$") or ""):lower()
  if extension == "lua" then
    files[#files + 1] = path
  elseif extension == "xml" then
    expandXml(path, readFile, files, report)
  else
    report[#report + 1] = path .. ": unsupported file type ignored"
  end
end

-- Ordered Lua paths (relative to the addon root) the flavor loads, and a report of what the kit ignored.
-- readFile(path) returns an XML file's text, or nil when it cannot be read.
function M.filesFor(parsed, flavor, readFile)
  local row = Flavors.get(flavor)
  local files, report = {}, {}
  for _, file in ipairs(parsed.files) do
    reportIgnoredDirectives(file, report)
    if allowedOn(file, row, report) then
      addFile(file.path, readFile, files, report)
    end
  end
  return files, report
end

return M
