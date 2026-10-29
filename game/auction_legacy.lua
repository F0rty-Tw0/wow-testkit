-- The legacy auction house (mists, vanilla, tbc): the "list" results the scenario supplies, read from w.mock.auction at call
-- time: { canQuery = true, legacy?, list = { { itemID, name?, texture?, count = 1, quality?, canUse = true, level = 0,
-- minBid = 0, minIncrement = 0, buyout = 0, bid = 0, highBidder = false, owner?, timeLeft = 2 } } }. A row without a name,
-- texture or quality reads the item store. The kit never filters or sorts a list, and the query and bid calls only record
-- a request (B13, B14). The modern family (game/auction.lua) shares the w.mock.auction store.
local M = {}

local Items = require("game.items")
local Requests = require("game.requests")
local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

local unpack = unpack

M.DEFAULTS = { auction = { canQuery = true, list = {} } }

-- source: assumed (B1, B15) the legacy client is what vanilla and tbc ship (their only auction window) and mists ships both
-- windows, so its default is the modern one; the scenario's `legacy` opens the other.
local LEGACY_DEFAULT = { vanilla = true, tbc = true, mists = false }

-- The row of the "list" results at index; nothing, counted as unscripted under name, for an index with no row or a list the
-- store does not hold (the kit supplies "list" only).
local function rowAt(w, kind, index, name)
  local row = kind == "list" and type(index) == "number" and w.mock.auction.list[index]
  if not row then
    WorldApi.markUnscripted(w, name)
  end
  return row
end

-- source: confirmed (B14) the 18 values in the wiki's order; assumed the defaults the row leaves open (one item, usable,
-- level 0, no bid, sale status 0) and that the full-name and level-header slots are nil.
local function itemInfo(w, kind, index)
  local row = rowAt(w, kind, index, "GetAuctionItemInfo")
  if not row then
    return
  end
  local name, texture, record = Items.rowFacts(w, row)
  return unpack({
    name,
    texture,
    row.count or 1,
    row.quality or record.quality,
    row.canUse ~= false,
    row.level or 0,
    nil,
    row.minBid or 0,
    row.minIncrement or 0,
    row.buyout or 0,
    row.bid or 0,
    row.highBidder == true,
    nil,
    row.owner,
    nil,
    0,
    row.itemID,
    true,
  }, 1, 18)
end

local function installReads(w)
  -- source: confirmed (B14) batch, then count; assumed the kit's list is one batch.
  define(w, "GetNumAuctionItems", function(kind)
    local count = kind == "list" and #w.mock.auction.list or 0
    return count, count
  end)
  define(w, "GetAuctionItemInfo", function(kind, index)
    return itemInfo(w, kind, index)
  end)
  define(w, "GetAuctionItemLink", function(kind, index)
    local row = rowAt(w, kind, index, "GetAuctionItemLink")
    return row and Items.rowLink(w, row)
  end)
  -- source: confirmed (B14) bands 1-4; assumed "medium" (2) when the row names none.
  define(w, "GetAuctionItemTimeLeft", function(kind, index)
    local row = rowAt(w, kind, index, "GetAuctionItemTimeLeft")
    return row and (row.timeLeft or 2)
  end)
  -- source: confirmed (B14) canQuery, canQueryAll; assumed both follow the store's canQuery.
  define(w, "CanSendAuctionQuery", function()
    local canQuery = w.mock.auction.canQuery ~= false
    return canQuery, canQuery
  end)
  define(w, "IsUsingLegacyAuctionClient", function()
    return w.mock.auction.legacy == true
  end)
end

-- source: assumed (B13) the calls change nothing here; the scenario plays the server's reply.
local REQUESTS = { "QueryAuctionItems", "PlaceAuctionBid" }

function M.install(w)
  local auction = w.mock.auction
  if auction.legacy == nil then
    auction.legacy = LEGACY_DEFAULT[w.flavor]
  end
  installReads(w)
  for _, name in ipairs(REQUESTS) do
    define(w, name, function(...)
      Requests.record(w, name, ...)
    end)
  end
end

return M
