-- Scenario hooks for the auction house window (Task 12.6): the opener and closer for s:openWindow("auction") and
-- s:auctionResults(patch), the server's reply to a query. The two API families (game/auction_legacy.lua, game/auction.lua)
-- read the same w.mock.auction store.
local M = {}

local Auction = require("game.auction")
local BlizzardData = require("blizzard_data")
local State = require("game.state")

-- The result keys in the order their events fire (assumed, B14, B15).
local KEYS = { "list", "browse", "items", "commodities", "owned" }

local function sortedKeys(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

-- The item ids a patch names, in result order. Raises for an items key that is not an itemKeyString.
local function itemIds(patch)
  local ids = {}
  for _, row in ipairs(patch.list or {}) do
    ids[#ids + 1] = row.itemID
  end
  for _, key in ipairs({ "browse", "owned" }) do
    for _, row in ipairs(patch[key] or {}) do
      ids[#ids + 1] = row.itemKey and row.itemKey.itemID
    end
  end
  for _, text in ipairs(sortedKeys(patch.items or {})) do
    local itemKey = Auction.parseKey(text)
    if not itemKey then
      error("auctionResults: bad item key '" .. tostring(text) .. "'", 3)
    end
    ids[#ids + 1] = itemKey.itemID
  end
  for itemID in pairs(patch.commodities or {}) do
    ids[#ids + 1] = itemID
  end
  return ids
end

-- Copies the ids into w.mock.items from the extract (B17). source: assumed without an extract an id the store lacks is
-- called "Kit item <id>", so the demo's id-only results still read as items.
local function hydrate(w, ids)
  BlizzardData.items(w, ids)
  for _, id in ipairs(w.client == nil and ids or {}) do
    w.mock.items[id] = w.mock.items[id] or { name = "Kit item " .. id }
  end
end

local EVENTS = {
  list = "AUCTION_ITEM_LIST_UPDATE",
  browse = "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
  owned = "OWNED_AUCTIONS_UPDATED",
}

local function fire(s, key, results)
  if EVENTS[key] then
    s:fireIfKnown(EVENTS[key])
  elseif key == "items" then
    for _, text in ipairs(sortedKeys(results)) do
      s:fireIfKnown("ITEM_SEARCH_RESULTS_UPDATED", Auction.parseKey(text))
    end
  else
    for _, itemID in ipairs(sortedKeys(results)) do
      s:fireIfKnown("COMMODITY_SEARCH_RESULTS_UPDATED", itemID)
    end
  end
end

-- Registers the auction opener and closer on windows (scenario_windows.lua's module) and s:auctionResults on Scenario.
function M.extend(Scenario, windows)
  -- Opens auction. data = { canQuery = true, legacy?, <result keys of s:auctionResults> }: the query gate and the family
  -- IsUsingLegacyAuctionClient answers (each flavor's default when unset), the window path, then the results.
  windows.openers.auction = function(s, data)
    data = data or {}
    s.w:setMock({ auction = { canQuery = data.canQuery ~= false, legacy = data.legacy } })
    windows.show(s, "auction")
    s:auctionResults(data)
  end
  windows.closers.auction = function(s)
    windows.hide(s, "auction")
    s:fireIfKnown("AUCTION_HOUSE_CLOSED")
  end

  -- Replaces each result key patch holds (list, browse, items, commodities, owned) with a copy, hydrates the item ids it
  -- names, then fires that key's event: a new result list replaces the old one (State.merge never deletes). The kit never
  -- filters or sorts (B13).
  function Scenario:auctionResults(patch)
    local w = self.w
    hydrate(w, itemIds(patch))
    for _, key in ipairs(KEYS) do
      if patch[key] ~= nil then
        w.mock.auction[key] = State.merge({}, patch[key])
      end
    end
    for _, key in ipairs(KEYS) do
      if patch[key] ~= nil then
        fire(self, key, w.mock.auction[key])
      end
    end
  end
end

return M
