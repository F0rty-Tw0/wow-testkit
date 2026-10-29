-- World map reads (B8, B9), from w.mock.maps and w.mock.zone at call time. A map record (Task 7.4's, read here, never
-- reinstalled) gains artID, groupID, layers = { UiMapLayerInfo, ... }, tiles = { [layerIndex] = { fileID, ... } } (row-major) and
-- explored = { UiMapExplorationInfo, ... }; zone.position = { x, y } is the player's place (0-1) on zone.mapID. With an extract
-- the map list fills at install and a map's art on its first art read; scenario data wins (BlizzardData.fill).
local M = {}

local BlizzardData = require("blizzard_data")
local State = require("game.state")
local WorldApi = require("world_api")
local WorldMapDb2 = require("game.worldmap_db2")
local define = State.define

M.DEFAULTS = {}

local ART_KEYS = { "layers", "tiles", "explored" }
local read = setmetatable({}, { __mode = "k" }) -- world -> { [uiMapID] = true }: maps whose art was already read from DB2

-- Fills the art keys the map record lacks from DB2, once per map.
local function readArt(w, uiMapID)
  read[w] = read[w] or {}
  if read[w][uiMapID] or not w.client then
    return
  end
  read[w][uiMapID] = true
  BlizzardData.fill(w, "maps", function()
    local art, record = WorldMapDb2.art(w, uiMapID), w.mock.maps[uiMapID]
    if not art then
      return nil
    end
    local missing = {}
    for _, key in ipairs(ART_KEYS) do
      if record[key] == nil then
        missing[key] = art[key]
      end
    end
    return { [uiMapID] = missing }
  end)
end

-- The map record for uiMapID with its art read, or nil (a map the mock lacks is marked unscripted, as GetMapInfo does).
local function recordOf(w, name, uiMapID)
  local record = type(uiMapID) == "number" and w.mock.maps[uiMapID]
  if not record then
    WorldApi.markUnscripted(w, name)
    return nil
  end
  readArt(w, uiMapID)
  return record
end

local function infoOf(id)
  return _G.C_Map.GetMapInfo(id)
end

-- The ids of the maps under parentID (all descendants when deep), ascending.
local function childIDs(maps, parentID, deep)
  local byParent = {}
  for id, record in pairs(maps) do
    local parent = record.parentMapID or 0
    byParent[parent] = byParent[parent] or {}
    byParent[parent][#byParent[parent] + 1] = id
  end
  local out, seen, pending = {}, {}, { parentID }
  while #pending > 0 do
    local parent = table.remove(pending)
    for _, id in ipairs(byParent[parent] or {}) do
      if not seen[id] then
        seen[id] = true
        out[#out + 1] = id
        pending[#pending + 1] = deep and id or nil
      end
    end
  end
  table.sort(out)
  return out
end

local function installChildren(w)
  -- source: confirmed (B8) the signature (api/retail/Map.lua:215); assumed the order (ascending mapID) and that mapType
  -- filters the result, descendants included.
  define(w, "C_Map.GetMapChildrenInfo", function(uiMapID, mapType, allDescendants)
    local out = {}
    for _, id in ipairs(childIDs(w.mock.maps, uiMapID, allDescendants)) do
      if mapType == nil or w.mock.maps[id].mapType == mapType then
        out[#out + 1] = infoOf(id)
      end
    end
    return out
  end)
end

local function installArt(w)
  define(w, "C_Map.GetMapArtID", function(uiMapID)
    local record = recordOf(w, "C_Map.GetMapArtID", uiMapID)
    return record and record.artID
  end)
  define(w, "C_Map.GetMapArtLayers", function(uiMapID)
    local record = recordOf(w, "C_Map.GetMapArtLayers", uiMapID)
    return record and record.layers
  end)
  define(w, "C_Map.GetMapArtLayerTextures", function(uiMapID, layerIndex)
    local record = recordOf(w, "C_Map.GetMapArtLayerTextures", uiMapID)
    return record and record.tiles and record.tiles[layerIndex]
  end)
  -- source: confirmed (B8) a boolean (api/retail/Map.lua:996); assumed a map has art when it has a layer.
  define(w, "C_Map.MapHasArt", function(uiMapID)
    local record = type(uiMapID) == "number" and w.mock.maps[uiMapID]
    if record then
      readArt(w, uiMapID)
    end
    return record and record.layers ~= nil and #record.layers > 0 or false
  end)
  define(w, "C_Map.GetMapGroupID", function(uiMapID)
    local record = recordOf(w, "C_Map.GetMapGroupID", uiMapID)
    return record and record.groupID
  end)
  -- source: assumed (B9) a map's overlays are all explored; the struct fields are confirmed (api/retail/MapExploration.lua:88).
  define(w, "C_MapExplorationInfo.GetExploredMapTextures", function(uiMapID)
    local record = recordOf(w, "C_MapExplorationInfo.GetExploredMapTextures", uiMapID)
    return record and record.explored
  end)
end

-- A Vector2D from the client's CreateVector2D, else a kit table with the same x, y and GetXY.
local function vector(x, y)
  if type(_G.CreateVector2D) == "function" then
    return _G.CreateVector2D(x, y)
  end
  return {
    x = x,
    y = y,
    GetXY = function(self)
      return self.x, self.y
    end,
  }
end

local function installPlayer(w)
  -- source: confirmed (B8) a Vector2D or nothing (api/retail/Map.lua:311); assumed the kit table when CreateVector2D is absent,
  -- and that only "player" has a position in the mock (as C_Map.GetBestMapForUnit, game/zone.lua:36).
  define(w, "C_Map.GetPlayerMapPosition", function(uiMapID, unit)
    local zone = w.mock.zone
    local at = zone.position
    if type(unit) == "string" and unit:lower() == "player" and uiMapID == zone.mapID and type(at) == "table" then
      return vector(at.x, at.y)
    end
  end)
  -- source: assumed (B8) the value is the engine's: the lowest-id map of mapType 0 (the cosmic map).
  define(w, "C_Map.GetFallbackWorldMapID", function()
    local lowest
    for id, record in pairs(w.mock.maps) do
      if record.mapType == 0 and (lowest == nil or id < lowest) then
        lowest = id
      end
    end
    return lowest
  end)
end

function M.install(w)
  installChildren(w)
  installArt(w)
  installPlayer(w)
  BlizzardData.fill(w, "maps", WorldMapDb2.maps)
end

return M
