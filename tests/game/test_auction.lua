-- The modern auction house (retail, forever, mists): browse, item, commodity and owned results the scenario supplies, read
-- back at call time (B15, B13). The scenario hook and the window path are tested here too (open fires the flavor's events).
local A = require("assert")
local G = require("tests.helpers.game")
local W = require("tests.helpers.windows")

local KEY = { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
local MODERN = {
  browse = { { itemKey = KEY, totalQuantity = 40, minPrice = 20, containsOwnerItem = false } },
  commodities = {
    [2589] = {
      { itemID = 2589, quantity = 30, unitPrice = 20, auctionID = 1 },
      { itemID = 2589, quantity = 10, unitPrice = 25, auctionID = 2 },
    },
  },
}

local function test_browse_then_commodity_results() -- (B15)
  W.scenario("retail", {}, function(s)
    _G.C_AuctionHouse.SendBrowseQuery({ searchString = "cloth", sorts = {}, filters = {}, itemClassFilters = {} })
    local log = W.watch(s.w, { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED" })
    s:auctionResults(MODERN)
    A.same(W.names(log), { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED" })
    A.eq(log[2][3], 2589)
    A.same({ #_G.C_AuctionHouse.GetBrowseResults(), _G.C_AuctionHouse.GetNumCommoditySearchResults(2589) }, { 1, 2 })
    A.eq(_G.C_AuctionHouse.GetCommoditySearchResultInfo(2589, 2).unitPrice, 25)
    A.eq(_G.C_AuctionHouse.GetCommoditySearchResultInfo(2589, 3), nil)
  end)
end

local function test_item_key_info_reads_the_item_store_assumed() -- (B15)
  G.withGame("retail", function(w)
    w:setMock({ auction = MODERN, items = { [2589] = { name = "Kit Cloth", quality = 1, icon = 132903, classID = 7 } } })
    local info = _G.C_AuctionHouse.GetItemKeyInfo(KEY)
    A.same({ info.itemID, info.itemName, info.iconFileID, info.isCommodity, info.isEquipment }, { 2589, "Kit Cloth", 132903, true, false })
    A.same({ info.quality, info.isPet, info.battlePetSpeciesID }, { 1, false, 0 })
    w:setMock({ items = { [25] = { name = "Kit Sword", classID = 2 } } })
    local sword = _G.C_AuctionHouse.GetItemKeyInfo({ itemID = 25 })
    A.same({ sword.isCommodity, sword.isEquipment }, { false, true })
    A.eq(_G.C_AuctionHouse.GetItemKeyInfo({ itemID = 1 }), nil)
  end)
end

local function test_item_search_results_by_item_key() -- (B15)
  W.scenario("retail", {}, function(s)
    local log = W.watch(s.w, { "ITEM_SEARCH_RESULTS_UPDATED" })
    s:auctionResults({ items = { ["25:0:0:0"] = { { itemKey = { itemID = 25 }, quantity = 1, auctionID = 9, buyoutAmount = 9000 } } } })
    A.same({ #log, log[1][3].itemID }, { 1, 25 })
    A.same({ _G.C_AuctionHouse.GetNumItemSearchResults({ itemID = 25 }), _G.C_AuctionHouse.GetNumItemSearchResults({ itemID = 26 }) }, { 1, 0 })
    A.eq(_G.C_AuctionHouse.GetItemSearchResultInfo({ itemID = 25 }, 1).buyoutAmount, 9000)
  end)
end

local function test_owned_auctions_and_a_new_result_list_replaces_the_old_one() -- (B15)
  W.scenario("retail", {}, function(s)
    local log = W.watch(s.w, { "OWNED_AUCTIONS_UPDATED" })
    s:auctionResults({
      owned = { { auctionID = 4, itemKey = KEY, status = 0, quantity = 3 }, { auctionID = 5, itemKey = KEY, status = 1, quantity = 1 } },
    })
    A.same({ #log, _G.C_AuctionHouse.GetNumOwnedAuctions(), #_G.C_AuctionHouse.GetOwnedAuctions() }, { 1, 2, 2 })
    A.eq(_G.C_AuctionHouse.GetOwnedAuctionInfo(2).auctionID, 5)
    s:auctionResults({ owned = { { auctionID = 6, itemKey = KEY, status = 0, quantity = 1 } } })
    A.same({ _G.C_AuctionHouse.GetNumOwnedAuctions(), _G.C_AuctionHouse.GetOwnedAuctionInfo(1).auctionID }, { 1, 6 })
  end)
end

local function test_results_hydrate_the_item_store_from_the_extract() -- (B17)
  local db2 = {
    itemsparse = 'return { [2589] = { Display_lang = "Kit Cloth", OverallQualityID = 1 } }',
    item = "return { [2589] = { IconFileDataID = 132903, ClassID = 7 } }",
  }
  W.scenario("retail", { db2 = db2 }, function(s)
    s:auctionResults(MODERN)
    A.same({ s.w.mock.items[2589].name, s.w.mock.items[2589].icon }, { "Kit Cloth", 132903 })
  end)
  W.scenario("retail", {}, function(s) -- no extract: the id-only demo still reads as an item
    s:auctionResults(MODERN)
    A.eq(_G.C_AuctionHouse.GetItemKeyInfo(KEY).itemName, "Kit item 2589")
  end)
end

local function test_bids_and_posts_record_only() -- (B13)
  G.withGame("retail", function(w)
    _G.C_AuctionHouse.PlaceBid(1, 400)
    A.same({ w.mock.requests[1].api, w.mock.requests[1].args[2] }, { "C_AuctionHouse.PlaceBid", 400 })
    A.eq(_G.C_AuctionHouse.PostItem({}, 2, 1, 5, 10), false)
    _G.C_AuctionHouse.SendSearchQuery(KEY, {}, false)
    _G.C_AuctionHouse.CloseAuctionHouse()
    local apis = {}
    for i, request in ipairs(w.mock.requests) do
      apis[i] = request.api
    end
    A.same(apis, {
      "C_AuctionHouse.PlaceBid",
      "C_AuctionHouse.PostItem",
      "C_AuctionHouse.SendSearchQuery",
      "C_AuctionHouse.CloseAuctionHouse",
    })
  end)
end

local function test_throttle_ready_by_default_assumed()
  G.withGame("retail", function()
    A.eq(_G.C_AuctionHouse.IsThrottledMessageSystemReady(), true)
    A.eq(_G.C_AuctionHouse.HasFullBrowseResults(), true)
  end)
end

local function test_open_auction_fires_the_flavors_window_path_assumed() -- (B2)
  W.scenario("tbc", {}, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "AUCTION_HOUSE_SHOW" })
    s:openWindow("auction", {})
    A.same(W.names(log), { "AUCTION_HOUSE_SHOW" })
  end)
  W.scenario("retail", {}, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "AUCTION_HOUSE_SHOW" })
    s:openWindow("auction", {})
    A.same({ W.names(log), log[1][3] }, { { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "AUCTION_HOUSE_SHOW" }, 21 })
  end)
end

local function test_open_sets_the_flags_then_fires_results_and_close_hides() -- (B2)
  W.scenario("mists", {}, function(s)
    local log = W.watch(s.w, { "AUCTION_HOUSE_SHOW", "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_CLOSED" })
    s:openWindow("auction", { canQuery = false, legacy = true, list = { { itemID = 2589, minBid = 1 } } })
    A.same(W.names(log), { "AUCTION_HOUSE_SHOW", "AUCTION_ITEM_LIST_UPDATE" })
    A.same({ _G.IsUsingLegacyAuctionClient(), _G.CanSendAuctionQuery() }, { true, false, false })
    s:closeWindow("auction")
    A.eq(W.names(log)[3], "AUCTION_HOUSE_CLOSED")
  end)
  W.scenario("retail", {}, function(s)
    local log = W.watch(s.w, { "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "AUCTION_HOUSE_CLOSED" })
    s:openWindow("auction", {})
    s:closeWindow("auction")
    A.same({ W.names(log), log[1][3] }, { { "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "AUCTION_HOUSE_CLOSED" }, 21 })
  end)
end

return function()
  test_browse_then_commodity_results()
  test_item_key_info_reads_the_item_store_assumed()
  test_item_search_results_by_item_key()
  test_owned_auctions_and_a_new_result_list_replaces_the_old_one()
  test_results_hydrate_the_item_store_from_the_extract()
  test_bids_and_posts_record_only()
  test_throttle_ready_by_default_assumed()
  test_open_auction_fires_the_flavors_window_path_assumed()
  test_open_sets_the_flags_then_fires_results_and_close_hides()
end
