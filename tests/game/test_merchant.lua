-- Merchant stock, buyback and repair, read from w.mock.merchant (B10, B11, B13).
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local STOCK = {
  items = {
    { itemID = 6948, name = "Kit Stone", texture = 134414, price = 100 },
    { itemID = 159, name = "Kit Water", texture = 132794, price = 25, stackCount = 5, numAvailable = 3, maxStack = 20 },
  },
  buyback = { { itemID = 2589, name = "Kit Cloth", texture = 132903, price = 13, quantity = 2 } },
  canRepair = true,
  repairCost = 1234,
}

local function test_legacy_merchant_tuple_on_classic_flavors() -- (B10)
  G.withGame("vanilla", function(w)
    w:setMock({ merchant = STOCK })
    A.same({ _G.GetMerchantNumItems(), _G.GetMerchantItemID(2) }, { 2, 159 })
    A.same({ _G.GetMerchantItemInfo(2) }, { "Kit Water", 132794, 25, 5, 3, true, true, false })
    A.same({ _G.GetMerchantItemInfo(1) }, { "Kit Stone", 134414, 100, 1, -1, true, true, false })
  end)
end

local function test_merchant_item_info_table_on_retail() -- (B10)
  G.withGame("retail", function(w)
    w:setMock({ merchant = STOCK })
    local info = _G.C_MerchantFrame.GetItemInfo(2)
    A.same(
      { info.name, info.texture, info.price, info.stackCount, info.numAvailable, info.isPurchasable, info.hasExtendedCost },
      { "Kit Water", 132794, 25, 5, 3, true, false }
    )
    A.eq(rawget(_G, "GetMerchantItemInfo"), nil)
  end)
end

local function test_row_without_a_name_reads_the_item_store() -- (B10)
  G.withGame("retail", function(w)
    w:setMock({ merchant = { items = { { itemID = 6948, price = 1 } } }, items = { [6948] = { name = "Kit Stone", icon = 134414, quality = 1 } } })
    local info = _G.C_MerchantFrame.GetItemInfo(1)
    A.same({ info.name, info.texture }, { "Kit Stone", 134414 })
    A.contains(_G.GetMerchantItemLink(1), "|Hitem:6948:")
  end)
end

local function test_costs_come_back_item_by_item() -- (B10)
  local cost = { texture = 111, value = 4, link = "|Hitem:2::|h[Kit Token]|h", name = "Kit Token" }
  G.withGame("tbc", function(w)
    w:setMock({ merchant = { items = { { itemID = 1, price = 0, costs = { cost } } } } })
    A.same({ _G.GetMerchantItemCostInfo(1), _G.GetMerchantItemCostInfo(2) }, { 1 })
    A.same({ _G.GetMerchantItemCostItem(1, 1) }, { 111, 4, "|Hitem:2::|h[Kit Token]|h", "Kit Token" })
    A.eq(select(8, _G.GetMerchantItemInfo(1)), true)
  end)
end

local function test_max_stack_buyback_and_repair_assumed() -- (B11)
  G.withGame("tbc", function(w)
    w:setMock({ merchant = STOCK })
    A.same({ _G.GetMerchantItemMaxStack(2), _G.GetMerchantItemMaxStack(1) }, { 20, 1 })
    A.same({ _G.GetNumBuybackItems(), _G.GetBuybackItemInfo(1) }, { 1, "Kit Cloth", 132903, 13, 2, -1, true, false })
    A.same({ _G.CanMerchantRepair(), _G.GetRepairAllCost() }, { true, 1234, true })
  end)
  G.withGame("retail", function(w)
    w:setMock({ merchant = STOCK })
    A.same({ _G.C_MerchantFrame.GetBuybackItemID(1), _G.C_MerchantFrame.GetNumJunkItems() }, { 2589, 0 })
  end)
end

local function test_no_extra_currencies_and_no_money_on_the_cursor_assumed() -- (B10) read by the window at open
  G.withGame("retail", function()
    A.same({ _G.C_MerchantFrame.GetMerchantCurrencies(), _G.GetCursorMoney(), _G.GetPlayerTradeMoney() }, { {}, 0, 0 })
  end)
end

local function test_empty_merchant_answers_zero_on_every_flavor()
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function()
      A.same({ _G.GetMerchantNumItems(), _G.GetNumBuybackItems(), _G.CanMerchantRepair() }, { 0, 0, false }, flavor)
      A.same({ _G.GetRepairAllCost() }, { 0, false }, flavor)
    end)
  end
end

local function test_buying_records_the_request_and_changes_nothing() -- (B13)
  G.withGame("retail", function(w)
    w:setMock({ merchant = STOCK, money = 500 })
    _G.BuyMerchantItem(2, 3)
    _G.BuybackItem(1)
    _G.RepairAllItems()
    A.same(w.mock.requests, {
      { api = "BuyMerchantItem", args = { 2, 3, n = 2 } },
      { api = "BuybackItem", args = { 1, n = 1 } },
      { api = "RepairAllItems", args = { n = 0 } },
    })
    A.same({ _G.GetMoney(), _G.C_MerchantFrame.GetItemInfo(2).numAvailable }, { 500, 3 })
  end)
end

return function()
  test_legacy_merchant_tuple_on_classic_flavors()
  test_merchant_item_info_table_on_retail()
  test_row_without_a_name_reads_the_item_store()
  test_costs_come_back_item_by_item()
  test_max_stack_buyback_and_repair_assumed()
  test_no_extra_currencies_and_no_money_on_the_cursor_assumed()
  test_empty_merchant_answers_zero_on_every_flavor()
  test_buying_records_the_request_and_changes_nothing()
end
