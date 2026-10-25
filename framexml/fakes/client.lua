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

function M.install(w)
  if not w.client then
    return
  end
  installStrings(w)
  Measure.useGlyphs(w, Client.glyphs(w.client))
  w:install("C_Texture.GetAtlasInfo", function(name)
    return atlasInfo(w.client, name)
  end, API_GATE)
end

return M
