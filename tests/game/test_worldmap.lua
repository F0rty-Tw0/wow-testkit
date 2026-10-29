-- The C_Map art, children and player-position reads and C_MapExplorationInfo, all from w.mock.maps and w.mock.zone.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

-- Kit Forest art: 1002 x 668 at 256-px tiles -> ceil(1002/256) = 4 columns, ceil(668/256) = 3 rows = 12 tiles.
local MAPS = {
  [947] = { name = "Kit World", mapType = 0, flags = 0 },
  [13] = { name = "Kit Continent", mapType = 2, parentMapID = 947, flags = 0 },
  [37] = {
    name = "Kit Forest",
    mapType = 3,
    parentMapID = 13,
    flags = 0,
    artID = 15,
    groupID = 4,
    layers = { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1, additionalZoomSteps = 0 } },
    tiles = { [1] = { 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012 } },
    explored = { { textureWidth = 256, textureHeight = 128, offsetX = 10, offsetY = 20, isShownByMouseOver = false, fileDataIDs = { 2001 } } },
  },
}

local function test_children_direct_and_all_descendants() -- (B8)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function(w)
      w:setMock({ maps = MAPS })
      A.same(_G.C_Map.GetMapChildrenInfo(13), { { mapID = 37, name = "Kit Forest", mapType = 3, parentMapID = 13, flags = 0 } }, flavor)
      local ids = {}
      for i, m in ipairs(_G.C_Map.GetMapChildrenInfo(947, nil, true)) do
        ids[i] = m.mapID
      end
      A.same(ids, { 13, 37 }, flavor)
      A.eq(_G.C_Map.GetMapChildrenInfo(947, 3, true)[1].mapID, 37, flavor)
      A.same(_G.C_Map.GetMapChildrenInfo(947, 3), {}, flavor) -- not a direct child
    end)
  end
end

local function test_art_layers_and_row_major_tiles() -- (B8, confirmed)
  -- source: blizzard_mapcanvas/blizzard_mapcanvasdetaillayer.lua:67 (extract retail 70575): textureIndex = (tileRow - 1) * numDetailTilesCols + tileCol
  G.withGame("retail", function(w)
    w:setMock({ maps = MAPS })
    A.same({ _G.C_Map.GetMapArtID(37), _G.C_Map.GetMapArtLayers(37)[1].tileWidth, #_G.C_Map.GetMapArtLayerTextures(37, 1) }, { 15, 256, 12 })
    A.eq(_G.C_Map.GetMapArtLayerTextures(37, 1)[5], 1005) -- row 2, column 1
    A.same({ _G.C_Map.GetMapGroupID(37), _G.C_Map.GetMapGroupID(13) }, { 4, nil })
    A.same({ _G.C_Map.GetMapArtID(13), _G.C_Map.GetMapArtLayers(13), _G.C_Map.GetMapArtLayerTextures(37, 2) }, {})
    -- MapUtil.GetDisplayableMapForPlayer (maputil.lua:77) walks up from the player's map to the first one with art
    A.same({ _G.C_Map.MapHasArt(37), _G.C_Map.MapHasArt(13), _G.C_Map.MapHasArt(99) }, { true, false, false })
  end)
end

local function test_player_position_only_on_the_zone_map() -- (B8)
  G.withGame("retail", function(w)
    w:setMock({ maps = MAPS, zone = { zone = "Kit Forest", mapID = 37, position = { x = 0.4, y = 0.6 } } })
    A.same({ _G.C_Map.GetPlayerMapPosition(37, "player"):GetXY() }, { 0.4, 0.6 })
    A.same({ _G.C_Map.GetPlayerMapPosition(13, "player"), _G.C_Map.GetBestMapForUnit("player") }, { nil, 37 })
    A.eq(_G.C_Map.GetPlayerMapPosition(37, "target"), nil) -- only "player" has a position in the mock
  end)
end

local function test_player_position_without_create_vector_2d_is_a_kit_table_assumed() -- (B8: a Vector2D or nil; the stand-in is assumed)
  G.withGame("retail", function(w)
    w:setMock({ zone = { mapID = 37, position = { x = 0.25, y = 0.75 } } })
    local create = _G.CreateVector2D
    _G.CreateVector2D = nil
    local pos = _G.C_Map.GetPlayerMapPosition(37, "player")
    _G.CreateVector2D = create
    A.same({ pos.x, pos.y, pos:GetXY() }, { 0.25, 0.75, 0.25, 0.75 })
  end)
end

local function test_explored_overlays_and_fallback_map_assumed() -- (B8 fallback id assumed, B9 "all overlays explored" assumed; the struct fields are confirmed)
  G.withGame("retail", function(w)
    w:setMock({ maps = MAPS })
    A.eq(_G.C_MapExplorationInfo.GetExploredMapTextures(37)[1].fileDataIDs[1], 2001)
    A.eq(_G.C_MapExplorationInfo.GetExploredMapTextures(13), nil)
    A.eq(_G.C_Map.GetFallbackWorldMapID(), 947)
  end)
end

return function()
  test_children_direct_and_all_descendants()
  test_art_layers_and_row_major_tiles()
  test_player_position_only_on_the_zone_map()
  test_player_position_without_create_vector_2d_is_a_kit_table_assumed()
  test_explored_overlays_and_fallback_map_assumed()
end
