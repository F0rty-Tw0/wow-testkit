-- Turns loaded Blizzard API docs plus Ketho's name lists into a per-flavor manifest of API facts.
--   python tools/run51.py --script tools/generate.lua <flavor>
-- reads $TESTKIT_HOME/mirror/{gethe,ketho}/<branch>/ and writes api/<flavor>/ plus api/versions.lua.
local M = {}

local GenerateDoc = require("tools.generate_doc")
local Manifest = require("manifest")

local SCRIPT_OBJECT = "ScriptObject"
local META_KEYS = { "flavor", "branch", "version", "mirrorCommit" }
local KNOWN_KINDS = { Enumeration = "enums", Structure = "structs", CallbackType = "callbacks" }

-- "UnitDocumentation.lua" -> "Unit"
local function fileKey(name)
  return (name:gsub("Documentation%.lua$", ""):gsub("%.lua$", ""))
end

local function enumFields(t)
  local fields = {}
  for _, f in ipairs(t.Fields or {}) do
    fields[f.Name] = f.EnumValue
  end
  return fields
end

-- Enum (with field values), struct and callback names, from every doc except widget (ScriptObject) docs.
local function knownTypes(entries)
  local known = { enums = {}, structs = {}, callbacks = {} }
  for _, entry in ipairs(entries) do
    if entry.doc.Type ~= SCRIPT_OBJECT then
      for _, t in ipairs(entry.doc.Tables or {}) do
        local kind = KNOWN_KINDS[t.Type]
        if kind then
          known[kind][t.Name] = kind == "enums" and enumFields(t) or true
        end
      end
    end
  end
  return known
end
M.knownTypes = knownTypes

-- Drops empty sections; returns nil when nothing is left.
local function prune(part)
  local kept = false
  for _, section in ipairs(Manifest.SECTIONS) do
    if next(part[section]) == nil then
      part[section] = nil
    else
      kept = true
    end
  end
  return kept and part or nil
end

local function toSet(list, skip)
  local set = {}
  for _, name in ipairs(list or {}) do
    if not (skip and skip[name]) then
      set[name] = true
    end
  end
  return set
end

-- The number globals LuaEnum.lua assigns (LE_*, NUM_LE_*): the engine injects them and no Blizzard Lua defines them.
local function numberGlobals(luaEnum)
  local legacy = {}
  for name, value in pairs(luaEnum) do
    if type(value) == "number" then
      legacy[name] = value
    end
  end
  return legacy
end

-- LuaEnum.lua's Constants tables (a live-client dump), their scalar members only: the engine's values for members no API
-- doc lists (row G40).
local function constantTables(luaEnum)
  local out = {}
  for name, members in pairs(luaEnum.Constants or {}) do
    if type(members) == "table" then
      out[name] = {}
      for key, value in pairs(members) do
        if type(value) ~= "table" and type(value) ~= "function" then
          out[name][key] = value
        end
      end
    end
  end
  return out
end

-- Ketho's CVars.lua returns { CVars, PTR }; CVars.var maps each name to { default, category, account, character,
-- secure, help }. Keys are lowercased because CVar names are case-insensitive (game/session.lua). PTR-only CVars stay out.
local function cvarDefaults(cvars)
  local out = {}
  for name, info in pairs(cvars[1].var) do
    out[name:lower()] = info[1]
  end
  return out
end

local function buildGlobals(ketho, functions)
  local events = {}
  for _, names in pairs(ketho.Events) do
    for name in pairs(toSet(names)) do
      events[name] = true
    end
  end
  return {
    api = toSet(ketho.GlobalAPI[1], functions),
    lua = toSet(ketho.GlobalAPI[2]),
    frames = toSet(ketho.Frames[1]),
    framexml = toSet(ketho.FrameXML[1]),
    events = events,
    widgets = ketho.WidgetAPI,
    legacy = numberGlobals(ketho.LuaEnum),
    constants = constantTables(ketho.LuaEnum),
    cvars = cvarDefaults(ketho.CVars),
  }
end

local function buildFiles(entries, ctx)
  local files = {}
  for _, entry in ipairs(entries) do
    local key = fileKey(entry.file)
    files[key] = files[key] or Manifest.empty()
    local adder = entry.doc.Type == SCRIPT_OBJECT and GenerateDoc.addWidget or GenerateDoc.addSystem
    adder(files[key], entry.doc, ctx)
  end
  for key, part in pairs(files) do
    files[key] = prune(part)
  end
  return files
end

-- Every namespace with at least one function in Ketho's GlobalAPI lists ("C_AuctionHouse", "table", ...).
local function listedNamespaces(ketho)
  local listed = {}
  for _, names in ipairs(ketho.GlobalAPI) do
    for _, name in ipairs(names) do
      local namespace = name:match("^(.+)%.[^.]+$")
      if namespace then
        listed[namespace] = true
      end
    end
  end
  return listed
end

-- Merges the file parts in sorted file order: the alphabetically last file wins a key that several define,
-- and each such key is recorded as "<kind>:<key> <earlier file> <later file>".
local function mergeFiles(manifest, files, duplicates)
  local names, owners = {}, {}
  for name in pairs(files) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    for _, section in ipairs(Manifest.SECTIONS) do
      for key in pairs(files[name][section] or {}) do
        local owner = section .. ":" .. key
        if owners[owner] then
          duplicates[#duplicates + 1] = owner .. " " .. owners[owner] .. " " .. name
        end
        owners[owner] = name
      end
    end
    Manifest.merge(manifest, files[name])
  end
  table.sort(duplicates)
end

-- entries: Docs.loadDir output; ketho: { GlobalAPI, Frames, FrameXML, WidgetAPI, Events } as loaded;
-- meta: { flavor, branch, version, mirrorCommit, kethoCommit } (kethoCommit goes to api/versions.lua only). Returns { manifest, globals, report, files }.
function M.build(entries, ketho, meta)
  local report = GenerateDoc.newReport()
  local files = buildFiles(entries, { known = knownTypes(entries), report = report, listed = listedNamespaces(ketho) })
  local manifest = Manifest.empty()
  for _, key in ipairs(META_KEYS) do
    manifest[key] = meta[key]
  end
  mergeFiles(manifest, files, report.duplicates)
  return { manifest = manifest, globals = buildGlobals(ketho, manifest.functions), report = report, files = files }
end

if (...) == "tools.generate" then
  return M
end
return require("tools.generate_io").main(M, ...)
