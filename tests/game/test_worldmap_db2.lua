-- World map data built from the extract's DB2 tables (game/worldmap_db2.lua): the map list, a map's art layers, tiles and
-- explored overlays, and scenario data winning over all of them. Every table is kit-authored (tests/helpers/windows.lua),
-- never a Blizzard row.
local A = require("assert")
local BlizzardData = require("blizzard_data")
local W = require("tests.helpers.windows")
local WorldMapDb2 = require("game.worldmap_db2")

local DB2 = {
  uimap = [[return {
    [13] = { ID = 13, Name_lang = "Kit Continent", Type = 2, ParentUiMapID = 947, Flags = 0 },
    [37] = { ID = 37, Name_lang = "Kit Forest", Type = 3, ParentUiMapID = 13, Flags = 6 },
    [947] = { ID = 947, Name_lang = "Kit World", Type = 0, ParentUiMapID = 0, Flags = 0 },
  }]],
  uimapxmapart = [[return {
    [1] = { ID = 1, UiMapID = 37, UiMapArtID = 16, PhaseID = 7 },
    [2] = { ID = 2, UiMapID = 37, UiMapArtID = 15, PhaseID = 0 },
  }]],
  uimapart = "return { [15] = { ID = 15, UiMapArtStyleID = 3 }, [16] = { ID = 16, UiMapArtStyleID = 4 } }",
  uimapartstylelayer = [[return {
    [9] = { ID = 9, UiMapArtStyleID = 3, LayerIndex = 0, LayerWidth = 768, LayerHeight = 256, TileWidth = 256, TileHeight = 256, MinScale = 1, MaxScale = 2, AdditionalZoomSteps = 1 },
  }]],
  uimaparttile = [[return {
    [21] = { ID = 21, UiMapArtID = 15, LayerIndex = 0, RowIndex = 0, ColIndex = 2, FileDataID = 1003 },
    [22] = { ID = 22, UiMapArtID = 15, LayerIndex = 0, RowIndex = 0, ColIndex = 0, FileDataID = 1001 },
    [23] = { ID = 23, UiMapArtID = 15, LayerIndex = 0, RowIndex = 0, ColIndex = 1, FileDataID = 1002 },
  }]],
  worldmapoverlay = [[return {
    [84] = { ID = 84, UiMapArtID = 15, TextureWidth = 256, TextureHeight = 128, OffsetX = 10, OffsetY = 20, HitRectTop = 1, HitRectBottom = 2, HitRectLeft = 3, HitRectRight = 4, Flags = 0 },
  }]],
  worldmapoverlaytile = [[return {
    [90] = { ID = 90, WorldMapOverlayID = 84, LayerIndex = 0, RowIndex = 0, ColIndex = 1, FileDataID = 2002 },
    [91] = { ID = 91, WorldMapOverlayID = 84, LayerIndex = 0, RowIndex = 0, ColIndex = 0, FileDataID = 2001 },
  }]],
}
local INDEX = {
  ["uimapxmapart.uimapid"] = "return { [37] = { 1, 2 } }",
  ["uimapartstylelayer.uimapartstyleid"] = "return { [3] = { 9 } }",
  ["uimaparttile.uimapartid"] = "return { [15] = { 21, 22, 23 } }",
  ["worldmapoverlay.uimapartid"] = "return { [15] = { 84 } }",
  ["worldmapoverlaytile.worldmapoverlayid"] = "return { [84] = { 90, 91 } }",
}
local OPTS = { db2 = DB2, index = INDEX }

local function test_maps_build_from_ui_map_rows()
  W.withWindows("retail", OPTS, function(w)
    A.same(_G.C_Map.GetMapInfo(37), { mapID = 37, name = "Kit Forest", mapType = 3, parentMapID = 13, flags = 6 }) -- filled at install
    A.same({ _G.C_Map.GetMapInfo(947).parentMapID, _G.C_Map.GetMapInfo(13).name }, { 0, "Kit Continent" })
    A.same({ w.mock.maps[37].artID, w.mock.maps[13].artID }, { 15, nil })
  end)
end

local function test_no_extract_builds_no_maps()
  W.withWindows("retail", {}, function(w)
    A.eq(WorldMapDb2.maps(w), nil)
    A.same(w.mock.maps, {})
  end)
end

local function test_phase_art_is_ignored_assumed() -- (B17: PhaseID ~= 0 is phased art; assumed)
  W.withWindows("retail", OPTS, function(w)
    A.eq(w.mock.maps[37].artID, 15) -- the phase 7 row (art 16) has the lower row ID
  end)
end

local function test_tiles_sort_by_layer_row_column()
  -- source: blizzard_mapcanvas/blizzard_mapcanvasdetaillayer.lua:67 (extract retail 70575): row-major, 0-based DB2 indexes
  W.withWindows("retail", OPTS, function(w)
    local art = WorldMapDb2.art(w, 37)
    A.same(art.tiles, { [1] = { 1001, 1002, 1003 } })
    A.same(art.layers, {
      { layerWidth = 768, layerHeight = 256, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 2, additionalZoomSteps = 1 },
    })
    A.same({ _G.C_Map.GetMapArtLayerTextures(37, 1) }, { { 1001, 1002, 1003 } }) -- the first art read fills the store
  end)
end

local function test_overlays_become_explored_textures_assumed() -- (B9: all explored, the draw flags false; assumed)
  W.withWindows("retail", OPTS, function(w)
    A.same(WorldMapDb2.art(w, 37).explored, {
      {
        textureWidth = 256,
        textureHeight = 128,
        offsetX = 10,
        offsetY = 20,
        isShownByMouseOver = false,
        isDrawOnTopLayer = false,
        fileDataIDs = { 2001, 2002 },
        hitRect = { top = 1, bottom = 2, left = 3, right = 4 },
      },
    })
  end)
end

local function test_map_without_art_builds_none()
  W.withWindows("retail", OPTS, function(w)
    A.eq(WorldMapDb2.art(w, 13), nil)
    A.same({ _G.C_Map.GetMapArtID(13), _G.C_Map.GetMapArtLayers(13) }, {})
  end)
end

local function test_scenario_map_wins_over_db2()
  W.withWindows("retail", OPTS, function(w)
    w:setMock({ maps = { [37] = { name = "Scenario Forest", tiles = { [1] = { 7 } } } } })
    BlizzardData.fill(w, "maps", WorldMapDb2.maps) -- the opener's fill: no key already set is overwritten
    A.same({ _G.C_Map.GetMapInfo(37).name, w.mock.maps[37].artID }, { "Scenario Forest", 15 })
    A.same(_G.C_Map.GetMapArtLayerTextures(37, 1), { 7 }) -- the scenario's tiles stand whole; DB2 adds none
    A.eq(_G.C_Map.GetMapArtLayers(37)[1].layerWidth, 768) -- a key the scenario left unset comes from DB2
  end)
end

return function()
  test_maps_build_from_ui_map_rows()
  test_no_extract_builds_no_maps()
  test_phase_art_is_ignored_assumed()
  test_tiles_sort_by_layer_row_column()
  test_overlays_become_explored_textures_assumed()
  test_map_without_art_builds_none()
  test_scenario_map_wins_over_db2()
end
