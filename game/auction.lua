-- The modern auction house (retail, forever, mists): the result shapes the scenario supplies, read from w.mock.auction at
-- call time: browse = { BrowseResultInfo }, items = { [itemKeyString] = { ItemSearchResultInfo } }, commodities = {
-- [itemID] = { CommoditySearchResultInfo } }, owned = { OwnedAuctionInfo }. itemKeyString is "itemID:itemLevel:itemSuffix:
-- battlePetSpeciesID", an absent field 0. The kit never filters, sorts or aggregates, and the query, bid and post calls only
-- record a request (B13, B15). The legacy family (game/auction_legacy.lua) shares the w.mock.auction store.
local M = {}

local Requests = require("game.requests")
local State = require("game.state")
local define = State.define

M.DEFAULTS = { auction = { browse = {}, items = {}, commodities = {}, owned = {} } }

-- The itemKeyString of an ItemKey ({ itemID, itemLevel?, itemSuffix?, battlePetSpeciesID? }).
function M.keyString(itemKey)
  return string.format("%d:%d:%d:%d", itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0, itemKey.battlePetSpeciesID or 0)
end

-- The ItemKey an itemKeyString names; nothing for a string that is not four numbers.
function M.parseKey(text)
  local id, level, suffix, species = tostring(text):match("^(%d+):(%d+):(%d+):(%d+)$")
  if id then
    return { itemID = tonumber(id), itemLevel = tonumber(level), itemSuffix = tonumber(suffix), battlePetSpeciesID = tonumber(species) }
  end
end

local EQUIPMENT_CLASSES = { [2] = true, [4] = true } -- weapon, armor

-- source: confirmed (B15) the ItemKeyInfo fields; assumed the name, quality and icon come from the item store, a pet never
-- (the kit models none), a commodity is an item with commodity results, equipment is a weapon or armor class item, and a
-- quality the store lacks is common (1). Nothing for an item the store lacks: the client's not-yet-cached answer.
local function keyInfo(w, itemKey)
  local record = type(itemKey) == "table" and w.mock.items[itemKey.itemID]
  if not (record and record.name) then
    return
  end
  return {
    itemID = itemKey.itemID,
    battlePetSpeciesID = itemKey.battlePetSpeciesID or 0,
    itemName = record.name,
    quality = record.quality or 1,
    iconFileID = record.icon,
    isPet = false,
    isCommodity = w.mock.auction.commodities[itemKey.itemID] ~= nil,
    isEquipment = EQUIPMENT_CLASSES[record.classID] == true,
  }
end

local function itemResults(w, itemKey)
  return type(itemKey) == "table" and itemKey.itemID and w.mock.auction.items[M.keyString(itemKey)] or {}
end

local function installResults(w)
  define(w, "C_AuctionHouse.GetBrowseResults", function()
    return w.mock.auction.browse
  end)
  -- source: assumed the scenario supplies every page, so there is nothing more to request.
  define(w, "C_AuctionHouse.HasFullBrowseResults", function()
    return true
  end)
  define(w, "C_AuctionHouse.GetItemKeyInfo", function(itemKey)
    return keyInfo(w, itemKey)
  end)
  define(w, "C_AuctionHouse.GetNumItemSearchResults", function(itemKey)
    return #itemResults(w, itemKey)
  end)
  define(w, "C_AuctionHouse.GetItemSearchResultInfo", function(itemKey, index)
    return itemResults(w, itemKey)[index]
  end)
  define(w, "C_AuctionHouse.GetNumCommoditySearchResults", function(itemID)
    return #(w.mock.auction.commodities[itemID] or {})
  end)
  define(w, "C_AuctionHouse.GetCommoditySearchResultInfo", function(itemID, index)
    return (w.mock.auction.commodities[itemID] or {})[index]
  end)
  define(w, "C_AuctionHouse.GetNumOwnedAuctions", function()
    return #w.mock.auction.owned
  end)
  define(w, "C_AuctionHouse.GetOwnedAuctions", function()
    return w.mock.auction.owned
  end)
  define(w, "C_AuctionHouse.GetOwnedAuctionInfo", function(index)
    return w.mock.auction.owned[index]
  end)
  -- source: assumed the client's throttle is always ready.
  define(w, "C_AuctionHouse.IsThrottledMessageSystemReady", function()
    return true
  end)
end

-- source: assumed (B13) the calls change nothing here; the scenario plays the server's reply. PostItem answers that no
-- confirmation is needed (its only immediate value).
local REQUESTS = { "SendBrowseQuery", "SendSearchQuery", "PlaceBid", "PostItem", "CloseAuctionHouse" }

function M.install(w)
  installResults(w)
  for _, name in ipairs(REQUESTS) do
    local api = "C_AuctionHouse." .. name
    define(w, api, function(...)
      Requests.record(w, api, ...)
      if name == "PostItem" then
        return false
      end
    end)
  end
end

return M
