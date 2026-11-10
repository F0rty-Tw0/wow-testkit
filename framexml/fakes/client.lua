-- The client extract (w.client) as the world's data: its GlobalStrings over the kit's test values, its glyph tables as the
-- text measure, and its atlas rows behind C_Texture.GetAtlasInfo. A no-op without an extract, so a world built with no
-- client is the kit's own.
local M = {}

local Client = require("client")
local Measure = require("ui.measure")

local STRING_GATE = { gate = "none" }
local API_GATE = { gate = "api" }

local function installStrings(w)
  for name, value in pairs(Client.strings(w.client) or {}) do
    w:install(name, value, STRING_GATE)
  end
end

local function atlasInfo(extract, name)
  local row = type(name) == "string" and Client.atlas(extract, name)
  if not row then
    return nil
  end
  return {
    width = row.width,
    height = row.height,
    leftTexCoord = row.left,
    rightTexCoord = row.right,
    topTexCoord = row.top,
    bottomTexCoord = row.bottom,
    file = row.file,
    tilesHorizontally = false,
    tilesVertically = false,
  }
end

-- Fills root (the Enum or Constants table the world installed) from the extract's tables: a missing table is copied,
-- an existing one gets only its missing fields, so the kit's values win. Non-table entries are skipped.
local function fillMissing(w, root, tables)
  for name, fields in pairs(tables) do
    if type(fields) == "table" then
      local target = rawget(root, name)
      if target == nil then
        target = {}
        w:rawWrite(root, name, target)
      end
      if type(target) == "table" then
        for key, value in pairs(fields) do
          if rawget(target, key) == nil then
            target[key] = value
          end
        end
      end
    end
  end
end

-- source: the client build's own API docs (Blizzard_APIDocumentationGenerated in the extract) list the enums and
-- constants its UI code reads; the kit's pinned api/<flavor> data can be older than the extract.
local function installApi(w)
  local api = Client.api(w.client)
  if not api then
    return
  end
  for root, tables in pairs({ Enum = api.enums, Constants = api.constants }) do
    local installed = rawget(_G, root) -- world.lua installBase sets both
    if type(installed) == "table" then
      fillMissing(w, installed, tables)
    end
  end
end

function M.install(w)
  if not w.client then
    return
  end
  installStrings(w)
  installApi(w)
  Measure.useGlyphs(w, Client.glyphs(w.client))
  w:install("C_Texture.GetAtlasInfo", function(name)
    return atlasInfo(w.client, name)
  end, API_GATE)
end

return M
