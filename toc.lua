-- Addon TOC files: names the addon, picks a flavor's TOC, parses its metadata and file lines, checks the declared
-- interface version, and lists the Lua and XML files a flavor loads (game-type directives applied).
local M = {}

local Flavors = require("tools.flavors")
local fs = require("fs")

local INTERFACE_KEY = "Interface"
local GAME_TYPE_DIRECTIVE = "AllowLoadGameType"
local UTF8_BOM = "^\239\187\191"
-- Localized: addon code may assign a global named os.
local osGetenv = os.getenv

-- Game types the client knows: those some flavor answers to, plus the client game types the kit has no flavor for
-- (warcraft.wiki.gg TOC_format). A game-type list naming none of them cannot exclude a file.
local KNOWN_GAME_TYPES = { wrath = true, cata = true, plunderstorm = true, wowhack = true }
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

-- True when root holds a TOC for name on any flavor (a flavor-suffixed one or the bare <name>.toc).
function M.exists(root, name)
  for _, flavor in ipairs(Flavors.list) do
    if fs.exists(M.select(root, name, flavor)) then
      return true
    end
  end
  return false
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
function M.addonName(root)
  local names, seen = {}, {}
  for _, file in ipairs(fs.list(root)) do
    local base = tocBase(file)
    if base and not seen[base] then
      seen[base] = true
      names[#names + 1] = base
    end
  end
  local folder = (root == "." and osGetenv("PWD") or root):gsub("\\", "/"):match("([^/]+)/*$")
  if folder and seen[folder] then
    return folder
  elseif #names == 1 then
    return names[1]
  end
  return nil, "cannot tell which TOC is the addon's in " .. root .. " (found " .. #names .. " TOC names)"
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
M.allowedOn = allowedOn

-- source: assumed (row BU2) "A [AllowLoadGameType mainline], B [AllowLoad Glue]" -> "A" on retail: a name whose
-- game-type list excludes row, or whose AllowLoad list lacks game (a glue-screen addon), is dropped.
local function allowedNames(value, row)
  local names = {}
  local guarded = value:gsub("%b[]", function(bracket)
    return (bracket:gsub(",", "\1"))
  end)
  for item in guarded:gmatch("[^,]+") do
    local dep = parseFileLine(trim((item:gsub("\1", ","))))
    local allowLoad = dep.directives.AllowLoad
    if dep.path ~= "" and allowedOn(dep, row, {}) and not (allowLoad and not allowLoad.game) then
      names[#names + 1] = dep.path
    end
  end
  return table.concat(names, ",")
end

-- source: confirmed (row G16) any word beginning Dep, and RequiredDeps, list addons that load first.
local function isRequiredKey(key)
  return key:sub(1, 3) == "Dep" or key == "RequiredDeps"
end

-- source: confirmed (row G16) a dependency directive may repeat, and later instances append to the list.
local function isListKey(key)
  return isRequiredKey(key) or key == "OptionalDeps"
end

function M.parse(text)
  local parsed = { meta = {}, files = {} }
  for raw in (text:gsub(UTF8_BOM, "")):gmatch("[^\r\n]+") do
    local line = trim(raw)
    local key, value = line:match("^##%s*(.-)%s*:%s*(.-)$")
    if key then
      if isListKey(key) and parsed.meta[key] then
        value = parsed.meta[key] .. "," .. value
      end
      parsed.meta[key] = value
    elseif line ~= "" and line:sub(1, 1) ~= "#" then
      parsed.files[#parsed.files + 1] = parseFileLine(line)
    end
  end
  parsed.savedVariables = splitList(parsed.meta.SavedVariables or "")
  parsed.savedVariablesPerCharacter = splitList(parsed.meta.SavedVariablesPerCharacter or "")
  return parsed
end

-- Adds the names of list to out, skipping any in seen.
local function appendNames(out, seen, list)
  for _, name in ipairs(splitList(list)) do
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
end

-- { required = { name, ... }, optional = { name, ... } } from the dependency directives of meta: Dependencies, RequiredDeps
-- and any directive beginning Dep are required, OptionalDeps optional. Directives are read in key order (the parsed
-- table keeps none); a name listed twice stays once, as required when it is in both. With flavor, each name's bracketed
-- directives are read and a name the flavor does not load is left out (allowedNames).
function M.dependencies(meta, flavor)
  local row = flavor and Flavors.get(flavor)
  local keys = {}
  for key in pairs(meta) do
    if isRequiredKey(key) then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local deps, seen = { required = {}, optional = {} }, {}
  for _, key in ipairs(keys) do
    appendNames(deps.required, seen, row and allowedNames(meta[key], row) or meta[key])
  end
  local optional = meta.OptionalDeps or ""
  appendNames(deps.optional, seen, row and allowedNames(optional, row) or optional)
  return deps
end

local function interfaceValues(meta, row)
  for _, key in ipairs(row.interfaceKeys) do
    if meta[key] then
      return meta[key]
    end
  end
  return meta[INTERFACE_KEY] or ""
end

local function majorOf(version)
  return math.floor(version / 10000)
end

-- Out of date within the client's version line: a lower value of the client's major, when no other flavor shares
-- that major. Assumption: the engine code that decides out of date versus incompatible is not visible.
local function outdatedInLine(items, flavor, row)
  local major = majorOf(row.tocVersion)
  for _, name in ipairs(Flavors.list) do
    if name ~= flavor and majorOf(Flavors.get(name).tocVersion) == major then
      return false
    end
  end
  for _, item in ipairs(items) do
    local version = tonumber(item)
    if version and majorOf(version) == major and version < row.tocVersion then
      return true
    end
  end
  return false
end

-- "load" | "outdated" | "ahead" | "not-declared". Values of the flavor's major.minor count first; a higher patch
-- wins over a lower one (the TOC already covers the current patch). With none, see outdatedInLine.
function M.declared(meta, flavor)
  local row = Flavors.get(flavor)
  local items = splitList(interfaceValues(meta, row))
  local lower, higher = false, false
  for _, item in ipairs(items) do
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
  return (lower or outdatedInLine(items, flavor, row)) and "outdated" or "not-declared"
end

local function reportIgnoredDirectives(file, report)
  for _, name in ipairs(sortedKeys(file.directives)) do
    if name ~= GAME_TYPE_DIRECTIVE then
      report[#report + 1] = file.path .. ": ignored directive [" .. name .. "]"
    end
  end
end

local function addFile(path, files, report)
  local extension = (path:match("%.(%w+)$") or ""):lower()
  if extension == "lua" or extension == "xml" then
    files[#files + 1] = path
  else
    report[#report + 1] = path .. ": unsupported file type ignored"
  end
end

-- Ordered Lua and XML paths (relative to the addon root) the flavor loads, and a report of what the kit ignored.
function M.filesFor(parsed, flavor)
  local row = Flavors.get(flavor)
  local files, report = {}, {}
  for _, file in ipairs(parsed.files) do
    reportIgnoredDirectives(file, report)
    if allowedOn(file, row, report) then
      addFile(file.path, files, report)
    end
  end
  return files, report
end

return M
