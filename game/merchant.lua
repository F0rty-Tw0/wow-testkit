-- The open merchant's stock, buyback list and repair state, read from w.mock.merchant at call time: { items = { { itemID,
-- name?, texture?, price = 0, stackCount = 1, numAvailable = -1, isPurchasable = true, isUsable = true, maxStack?, costs? = {
-- { texture, value, link?, name? } } } }, buyback = { { itemID, name?, texture?, price, quantity = 1, numAvailable?, isUsable =
-- true, isBound = false } }, canRepair = false, repairCost = 0, junk = 0 }. A row without a name or texture reads the item
-- store (B10). The buy and repair calls only record a request (B13).
local M = {}

local Items = require("game.items")
local Requests = require("game.requests")
local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

local unpack = unpack

M.DEFAULTS = { merchant = { items = {}, buyback = {}, canRepair = false, repairCost = 0, junk = 0 } }

-- The stock row (list "items") or buyback row (list "buyback") at index; nothing, counted as unscripted under name, for an
-- index with no row.
local function rowAt(w, list, index, name)
  local row = type(index) == "number" and w.mock.merchant[list][index]
  if not row then
    WorldApi.markUnscripted(w, name)
  end
  return row
end

-- source: confirmed (B10) the fields; assumed the defaults the row leaves open (price 0, one per stack, unlimited, purchasable
-- and usable) and that hasExtendedCost is "the row has costs".
local function stockInfo(w, index, name)
  local row = rowAt(w, "items", index, name)
  if not row then
    return
  end
  local itemName, texture = Items.rowFacts(w, row)
  return {
    name = itemName,
    texture = texture,
    price = row.price or 0,
    stackCount = row.stackCount or 1,
    numAvailable = row.numAvailable or -1,
    isPurchasable = row.isPurchasable ~= false,
    isUsable = row.isUsable ~= false,
    hasExtendedCost = #(row.costs or {}) > 0,
    currencyID = row.currencyID,
    spellID = row.spellID,
  }
end

local STOCK_FIELDS =
  { "name", "texture", "price", "stackCount", "numAvailable", "isPurchasable", "isUsable", "hasExtendedCost", "currencyID", "spellID" }

local function installStock(w)
  define(w, "GetMerchantNumItems", function()
    return #w.mock.merchant.items
  end)
  define(w, "GetMerchantItemID", function(index)
    local row = rowAt(w, "items", index, "GetMerchantItemID")
    return row and row.itemID
  end)
  define(w, "GetMerchantItemLink", function(index)
    local row = rowAt(w, "items", index, "GetMerchantItemLink")
    return row and Items.rowLink(w, row)
  end)
  -- source: confirmed (B10) the mists, vanilla and tbc tuple; retail and forever answer the struct below.
  define(w, "GetMerchantItemInfo", function(index)
    local info = stockInfo(w, index, "GetMerchantItemInfo")
    if info then
      local out = {}
      for i, key in ipairs(STOCK_FIELDS) do
        out[i] = info[key]
      end
      return unpack(out, 1, #STOCK_FIELDS)
    end
  end)
  define(w, "C_MerchantFrame.GetItemInfo", function(index)
    return stockInfo(w, index, "C_MerchantFrame.GetItemInfo")
  end)
  -- source: assumed (B11) the item's stack size is the default; one without a stack size is 1.
  define(w, "GetMerchantItemMaxStack", function(index)
    local row = rowAt(w, "items", index, "GetMerchantItemMaxStack")
    if row then
      local _, _, record = Items.rowFacts(w, row)
      return row.maxStack or record.stackCount or 1
    end
  end)
  define(w, "GetMerchantItemCostInfo", function(index)
    local row = rowAt(w, "items", index, "GetMerchantItemCostInfo")
    return row and #(row.costs or {})
  end)
  define(w, "GetMerchantItemCostItem", function(index, itemIndex)
    local row = rowAt(w, "items", index, "GetMerchantItemCostItem")
    local cost = row and type(itemIndex) == "number" and (row.costs or {})[itemIndex]
    if cost then
      return cost.texture, cost.value, cost.link, cost.name
    end
  end)
  define(w, "C_MerchantFrame.GetNumJunkItems", function()
    return w.mock.merchant.junk
  end)
  -- source: assumed (B10) the extra currencies a merchant takes: none (the window reads #currencies at open, merchantframe.lua:970).
  define(w, "C_MerchantFrame.GetMerchantCurrencies", function()
    return {}
  end)
end

-- source: confirmed (B11) the return list; assumed that a buyback row is unlimited (-1, as in stock; the window compares it to 0), usable and unbound unless it says otherwise.
local function installBuyback(w)
  define(w, "GetNumBuybackItems", function()
    return #w.mock.merchant.buyback
  end)
  define(w, "GetBuybackItemInfo", function(slot)
    local row = rowAt(w, "buyback", slot, "GetBuybackItemInfo")
    if row then
      local name, texture = Items.rowFacts(w, row)
      return name, texture, row.price or 0, row.quantity or 1, row.numAvailable or -1, row.isUsable ~= false, row.isBound == true
    end
  end)
  define(w, "C_MerchantFrame.GetBuybackItemID", function(slot)
    local row = rowAt(w, "buyback", slot, "C_MerchantFrame.GetBuybackItemID")
    return row and row.itemID
  end)
end

-- source: confirmed (B11) GetRepairAllCost returns the cost, then whether the merchant repairs.
local function installRepair(w)
  define(w, "CanMerchantRepair", function()
    return w.mock.merchant.canRepair == true
  end)
  define(w, "GetRepairAllCost", function()
    local merchant = w.mock.merchant
    return merchant.repairCost, merchant.canRepair == true
  end)
end

-- source: assumed (B13) the calls change nothing here; the scenario plays the server's reply.
local REQUESTS = { "BuyMerchantItem", "BuybackItem", "RepairAllItems" }

function M.install(w)
  installStock(w)
  installBuyback(w)
  installRepair(w)
  for _, name in ipairs(REQUESTS) do
    define(w, name, function(...)
      Requests.record(w, name, ...)
    end)
  end
end

return M
