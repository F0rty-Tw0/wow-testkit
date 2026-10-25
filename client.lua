-- The client extract tools/client writes under <home>/client/<flavor>/<build>/ (layout: docs/client-sources.md): finds the
-- newest one for a flavor and reads strings, atlas rows and glyph tables out of it. Read-only, and nothing here runs
-- unless a caller asks: the kit consumers read w.client, which only preview.lua and the tk entry points fill in.
local M = {}

local ClientGlyphs = require("client_glyphs")
local Home = require("home")
local fs = require("fs")

-- Lua 5.1 compiles with loadstring; load is the fallback for the pure modules' tests on 5.4.
local compile = loadstring or load

local IMAGE_EXTENSIONS = { blp = true, tga = true, png = true }

-- Per-extract caches (strings by locale, the atlas table, glyph tables, DB2 tables); gone with the extract.
local caches = setmetatable({}, { __mode = "k" })

local function cacheOf(extract)
  caches[extract] = caches[extract] or { strings = {}, glyphs = {}, db2 = {} }
  return caches[extract]
end

-- The table the Lua file at path returns, or nil when it is missing, does not compile, raises or returns no table.
local function readTable(path)
  local text = fs.readFile(path)
  local chunk = text and compile(text, "@" .. path)
  if not chunk then
    return nil
  end
  local ok, value = pcall(chunk)
  return ok and type(value) == "table" and value or nil
end

local function lowerSlashed(key)
  return (tostring(key):lower():gsub("\\", "/"))
end

local function fileName(key)
  return lowerSlashed(key):match("([^/]*)$")
end

local function withoutImageExtension(key)
  local base, extension = key:match("^(.*)%.(%w+)$")
  return base and IMAGE_EXTENSIONS[extension] and base or key
end

-- extract.dir-relative path of a kind's file for key (see M.path).
local RELATIVE = {
  code = function(key)
    return "code/" .. lowerSlashed(key)
  end,
  strings = function(locale)
    return "strings/" .. tostring(locale) .. ".lua"
  end,
  art = function(key)
    if type(key) == "number" then
      return "art/by-id/" .. key .. ".png"
    end
    return "art/" .. withoutImageExtension(lowerSlashed(key)) .. ".png"
  end,
  atlas = function(name)
    return "art/atlas/" .. lowerSlashed(name) .. ".png"
  end,
  font = function(key)
    return "fonts/" .. fileName(key)
  end,
  glyphs = function(key)
    return "fonts/glyphs/" .. fileName(key) .. ".lua"
  end,
  db2 = function(key)
    return "db2/" .. lowerSlashed(key) .. ".lua"
  end,
}

-- The extract in dir (its manifest table plus dir and flavor), or nil when the manifest is missing or does not load.
function M.load(dir, flavor)
  local extract = readTable(dir .. "/manifest.lua")
  if not extract then
    return nil
  end
  extract.dir, extract.flavor = dir, flavor
  return extract
end

local function buildsNewestFirst(root)
  local builds = {}
  for _, name in ipairs(fs.list(root)) do
    if tonumber(name) then
      builds[#builds + 1] = name
    end
  end
  table.sort(builds, function(a, b)
    return tonumber(a) > tonumber(b)
  end)
  return builds
end

local function scan(flavor, getenv)
  local root = Home.dir(getenv) .. "/client/" .. flavor
  if not fs.isdir(root) then
    return nil
  end
  for _, build in ipairs(buildsNewestFirst(root)) do
    local extract = M.load(root .. "/" .. build, flavor)
    if extract then
      return extract
    end
  end
  return nil
end

-- The extract with the highest build number whose manifest loads under the testkit home (an interrupted extract of a
-- newer build is skipped), or nil when there is no home, no folder for the flavor or no manifest loads. Never raises.
function M.find(flavor, getenv)
  local ok, extract = pcall(scan, flavor, getenv)
  return ok and extract or nil
end

-- Path of the file for key in the extract, or nil when it is not there. kind: code strings art atlas font glyphs db2.
-- Keys are lowercased with "\" turned into "/" (strings takes the locale as written; font and glyphs reduce to the file
-- name; art takes a path with or without an image extension, or a fileID number).
function M.path(extract, kind, key)
  local relative = RELATIVE[kind]
  if not relative then
    error("client: unknown kind '" .. tostring(kind) .. "'", 2)
  end
  local path = extract.dir .. "/" .. relative(key)
  return fs.exists(path) and path or nil
end

-- The extract's GlobalStrings for locale (default: the extract's first), or nil.
function M.strings(extract, locale)
  locale = locale or (extract.locales and extract.locales[1])
  if not locale then
    return nil
  end
  local cache = cacheOf(extract).strings
  if cache[locale] == nil then
    local path = M.path(extract, "strings", locale)
    cache[locale] = path and readTable(path) or false
  end
  return cache[locale] or nil
end

local CHUNK = 10000 -- ids per file of a chunked table; tools/client/db2_export.py writes the same number

-- A table that answers t[id] from db2/<name>/<id // CHUNK>.lua, loading each chunk on the first lookup in it. A chunk
-- that is missing or does not load answers nil for its ids. Only t[id] works on it: no pairs, no length.
local function chunkedTable(dir)
  local chunks = {}
  return setmetatable({}, {
    __index = function(_, id)
      if type(id) ~= "number" or id ~= id then -- id ~= id: NaN, which no table can hold as a key
        return nil
      end
      local number = math.floor(id / CHUNK)
      if chunks[number] == nil then
        chunks[number] = readTable(dir .. "/" .. number .. ".lua") or false
      end
      return chunks[number] and chunks[number][id] or nil
    end,
  })
end

-- The DB2 table name (any case) exported to the extract, { [id] = { Field = value } }, or nil when the extract is nil
-- or has no such table. The spell and item tables are chunked on disk, so they come back as a table that loads a chunk
-- on its first lookup (see chunkedTable); the others load whole on the first lookup. Callers read it, never write.
function M.db2(extract, name)
  if not extract then
    return nil
  end
  local cache = cacheOf(extract).db2
  local key = lowerSlashed(name)
  if cache[key] == nil then
    local dir = extract.dir .. "/db2/" .. key
    local path = M.path(extract, "db2", key)
    cache[key] = (fs.isdir(dir) and chunkedTable(dir)) or (path and readTable(path)) or false
  end
  return cache[key] or nil
end

-- The atlas row { name, file, width, height, left, right, top, bottom } for name (any case), or nil. atlas.lua is
-- read on the first lookup, not when the extract is found.
function M.atlas(extract, name)
  local cache = cacheOf(extract)
  if cache.atlas == nil then
    cache.atlas = readTable(extract.dir .. "/atlas.lua") or false
  end
  return cache.atlas and cache.atlas[lowerSlashed(name)] or nil
end

-- A glyph table that measures: { upm, notdef, advance, kern } with the fields client_glyphs reads present.
local function usableGlyphs(glyphs)
  local usable = glyphs and type(glyphs.upm) == "number" and glyphs.upm > 0 and type(glyphs.advance) == "table"
  if not usable then
    return nil
  end
  glyphs.notdef = glyphs.notdef or 0
  glyphs.kern = glyphs.kern or {}
  return glyphs
end

local function glyphEntry(extract, fontFile)
  local path = M.path(extract, "glyphs", fontFile)
  local glyphs = path and usableGlyphs(readTable(path))
  if not glyphs then
    return false
  end
  return {
    width = function(size, flags, text)
      return ClientGlyphs.width(glyphs, size, flags, text)
    end,
  }
end

-- A table for Measure.useGlyphs: indexing it by a font file as an addon spells it ("Fonts\\FRIZQT__.TTF") loads that
-- font's glyph table on first use and answers { width = function(size, flags, text) }, or nil when the extract has none.
function M.glyphs(extract)
  local entries = cacheOf(extract).glyphs
  return setmetatable({}, {
    __index = function(_, fontFile)
      if type(fontFile) ~= "string" then
        return nil
      end
      local key = fileName(fontFile)
      if entries[key] == nil then
        entries[key] = glyphEntry(extract, fontFile)
      end
      return entries[key] or nil
    end,
  })
end

return M
