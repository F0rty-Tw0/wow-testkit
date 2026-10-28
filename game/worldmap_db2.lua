-- World map data built from the client extract's DB2 tables (B17): the map list and one map's art layers, tiles and explored
-- overlays. Kept apart from the readers (game/worldmap.lua), which never touch DB2. Builders return a table for
-- BlizzardData.fill, so scenario data wins and no extract means nil. Every lookup goes through an index file; only UiMap
-- is walked whole.
local M = {}

local BlizzardData = require("blizzard_data")

-- source: assumed (B17) a UiMapXMapArt row with PhaseID ~= 0 is art for a phase, so the map's own art is the first row
-- (ascending by row ID) with PhaseID 0.
local function artIDOf(w, uiMapID)
  for _, row in ipairs(BlizzardData.rowsBy(w, "UiMapXMapArt", "UiMapID", uiMapID)) do
    if row.PhaseID == 0 then
      return row.UiMapArtID
    end
  end
  return nil
end

-- { [uiMapID] = { name, mapType, parentMapID, flags, artID? } } for every UiMap row, or nil without an extract or a table.
function M.maps(w)
  local rows = BlizzardData.table(w, "UiMap")
  if not rows then
    return nil
  end
  local out = {}
  for id, row in pairs(rows) do
    out[id] = { name = row.Name_lang, mapType = row.Type, parentMapID = row.ParentUiMapID, flags = row.Flags, artID = artIDOf(w, id) }
  end
  return out
end

local function byLayerIndex(a, b)
  return a.LayerIndex < b.LayerIndex
end

-- source: confirmed (B8) blizzard_mapcanvas/blizzard_mapcanvasdetaillayer.lua:67 (extract retail 70575): the client reads
-- textures[(tileRow - 1) * numDetailTilesCols + tileCol], so a layer's tiles go in row-major order.
local function byLayerRowColumn(a, b)
  if a.LayerIndex ~= b.LayerIndex then
    return a.LayerIndex < b.LayerIndex
  end
  if a.RowIndex ~= b.RowIndex then
    return a.RowIndex < b.RowIndex
  end
  return a.ColIndex < b.ColIndex
end

-- The kit's layers (UiMapLayerInfo, ascending LayerIndex) and the style layer position each DB2 LayerIndex lands on.
local function layersOf(w, styleID)
  local rows = BlizzardData.rowsBy(w, "UiMapArtStyleLayer", "UiMapArtStyleID", styleID)
  table.sort(rows, byLayerIndex)
  local layers, position = {}, {}
  for i, row in ipairs(rows) do
    layers[i] = {
      layerWidth = row.LayerWidth,
      layerHeight = row.LayerHeight,
      tileWidth = row.TileWidth,
      tileHeight = row.TileHeight,
      minScale = row.MinScale,
      maxScale = row.MaxScale,
      additionalZoomSteps = row.AdditionalZoomSteps,
    }
    position[row.LayerIndex] = i
  end
  return layers, position
end

local function tilesOf(w, artID, position)
  local rows, tiles = BlizzardData.rowsBy(w, "UiMapArtTile", "UiMapArtID", artID), {}
  table.sort(rows, byLayerRowColumn)
  for _, row in ipairs(rows) do
    local layer = position[row.LayerIndex]
    if layer then
      tiles[layer] = tiles[layer] or {}
      tiles[layer][#tiles[layer] + 1] = row.FileDataID
    end
  end
  return tiles
end

-- source: assumed (B9) every overlay is explored and none is a mouse-over or top-layer one: no layout carries the flags the
-- client would derive isShownByMouseOver and isDrawOnTopLayer from, and which overlays are explored is the server's.
local function exploredOf(w, artID)
  local out = {}
  for _, overlay in ipairs(BlizzardData.rowsBy(w, "WorldMapOverlay", "UiMapArtID", artID)) do
    local tiles, ids = BlizzardData.rowsBy(w, "WorldMapOverlayTile", "WorldMapOverlayID", overlay.ID), {}
    table.sort(tiles, byLayerRowColumn)
    for i, tile in ipairs(tiles) do
      ids[i] = tile.FileDataID
    end
    out[#out + 1] = {
      textureWidth = overlay.TextureWidth,
      textureHeight = overlay.TextureHeight,
      offsetX = overlay.OffsetX,
      offsetY = overlay.OffsetY,
      isShownByMouseOver = false,
      isDrawOnTopLayer = false,
      fileDataIDs = ids,
      hitRect = { top = overlay.HitRectTop, bottom = overlay.HitRectBottom, left = overlay.HitRectLeft, right = overlay.HitRectRight },
    }
  end
  return out
end

-- { layers, tiles = { [layerIndex] = { fileID, ... } }, explored? } for the art of map uiMapID (its artID in w.mock.maps),
-- or nil without an extract, an art id, a UiMapArt row or a style layer. explored is absent when the art has no overlay.
function M.art(w, uiMapID)
  local record, arts = w.mock.maps[uiMapID], BlizzardData.table(w, "UiMapArt")
  local artID = record and record.artID
  local art = artID and arts and arts[artID]
  if not art then
    return nil
  end
  local layers, position = layersOf(w, art.UiMapArtStyleID)
  if #layers == 0 then
    return nil
  end
  local explored = exploredOf(w, artID)
  return { layers = layers, tiles = tilesOf(w, artID, position), explored = #explored > 0 and explored or nil }
end

return M
