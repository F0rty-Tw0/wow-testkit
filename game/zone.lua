-- Zone texts, guild counts and the map the player stands in, read from w.mock at call time: zone = { zone, real, sub,
-- minimap, mapID }, maps = { [uiMapID] = { name, mapType, parentMapID, flags } } and guild = { total, online }. Use
-- false to clear a text or the map id a patch set earlier.
local M = {}

local State = require("game.state")
local Units = require("units")
local WorldApi = require("world_api")
local define = State.define

M.DEFAULTS = { zone = { zone = "", sub = "" }, maps = {}, guild = { total = 0, online = 0 } }

local function text(value)
  return type(value) == "string" and value ~= "" and value or nil
end

-- source: assumed (row G14) the real zone text falls back to the zone text, and the minimap text to the subzone and
-- then the zone; "" for an unknown zone (no page says).
local function installTexts(w)
  define(w, "GetZoneText", function()
    return text(w.mock.zone.zone) or ""
  end)
  define(w, "GetRealZoneText", function()
    return text(w.mock.zone.real) or text(w.mock.zone.zone) or ""
  end)
  -- source: confirmed (row G14) "" outside a subzone.
  define(w, "GetSubZoneText", function()
    return text(w.mock.zone.sub) or ""
  end)
  define(w, "GetMinimapZoneText", function()
    local zone = w.mock.zone
    return text(zone.minimap) or text(zone.sub) or text(zone.zone) or ""
  end)
end

local function installMap(w)
  -- source: confirmed (row G14) a uiMapID or nothing; assumed that only "player" (or the player's name, row G24) has a
  -- map in the mock.
  define(w, "C_Map.GetBestMapForUnit", function(unit)
    if type(w.mock.zone.mapID) == "number" and type(unit) == "string" and Units.standsFor(w, unit, "player") then
      return w.mock.zone.mapID
    end
  end)
  -- source: confirmed (row G14) the fields, parentMapID 0 with no parent; assumed that an unknown map gives nothing.
  define(w, "C_Map.GetMapInfo", function(mapID)
    local record = type(mapID) == "number" and w.mock.maps[mapID]
    if not record then
      WorldApi.markUnscripted(w, "C_Map.GetMapInfo")
      return nil
    end
    return {
      mapID = mapID,
      name = record.name,
      mapType = record.mapType,
      parentMapID = record.parentMapID or 0,
      flags = record.flags,
    }
  end)
end

function M.install(w)
  installTexts(w)
  installMap(w)
  -- source: confirmed (row G14) numTotal, numOnline: two values, both 0 without a guild.
  define(w, "GetNumGuildMembers", function()
    return w.mock.guild.total, w.mock.guild.online
  end)
end

return M
