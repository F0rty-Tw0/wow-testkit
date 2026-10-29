-- The legacy auction house (mists, vanilla, tbc): the list the scenario supplies, read back at call time (B14, B13).
local A = require("assert")
local G = require("tests.helpers.game")
local H = require("tests.helpers.world")
local W = require("tests.helpers.windows")

local LIST = {
  list = {
    {
      itemID = 2589,
      name = "Kit Cloth",
      texture = 132903,
      count = 20,
      quality = 1,
      minBid = 100,
      minIncrement = 5,
      buyout = 400,
      owner = "Kit Seller",
      timeLeft = 3,
    },
  },
}

local function test_query_records_and_results_arrive_with_the_scenario() -- (B13, B14)
  W.scenario("vanilla", {}, function(s)
    _G.QueryAuctionItems("cloth")
    A.same({ s.w.mock.requests[1].api, _G.GetNumAuctionItems("list") }, { "QueryAuctionItems", 0, 0 })
    local log = W.watch(s.w, { "AUCTION_ITEM_LIST_UPDATE" })
    s:auctionResults(LIST)
    A.same({ #log, _G.GetNumAuctionItems("list") }, { 1, 1, 1 })
  end)
end

local function test_auction_item_tuple_and_time_left() -- (B14)
  G.withGame("vanilla", function(w)
    w:setMock({ auction = LIST })
    A.same(
      { _G.GetAuctionItemInfo("list", 1) },
      { "Kit Cloth", 132903, 20, 1, true, 0, nil, 100, 5, 400, 0, false, nil, "Kit Seller", nil, 0, 2589, true }
    )
    A.same({ _G.GetAuctionItemTimeLeft("list", 1), _G.CanSendAuctionQuery() }, { 3, true, true })
    A.contains(_G.GetAuctionItemLink("list", 1), "|Hitem:2589:")
    A.same({ _G.GetAuctionItemInfo("list", 2) }, {})
    A.eq(w.unscripted.GetAuctionItemInfo, 1)
  end)
end

local function test_a_row_without_a_name_reads_the_item_store() -- (B14)
  G.withGame("tbc", function(w)
    w:setMock({
      auction = { list = { { itemID = 2589, minBid = 1 } } },
      items = { [2589] = { name = "Kit Cloth", icon = 132903, quality = 1 } },
    })
    A.same({ _G.GetAuctionItemInfo("list", 1) }, { "Kit Cloth", 132903, 1, 1, true, 0, nil, 1, 0, 0, 0, false, nil, nil, nil, 0, 2589, true })
  end)
end

local function test_bids_record_only_and_the_query_gate_follows_the_store() -- (B13)
  G.withGame("tbc", function(w)
    _G.PlaceAuctionBid("list", 1, 400)
    A.same({ w.mock.requests[1].api, w.mock.requests[1].args[3] }, { "PlaceAuctionBid", 400 })
    w:setMock({ auction = { canQuery = false } })
    A.same({ _G.CanSendAuctionQuery() }, { false, false })
  end)
end

local function test_families_follow_the_flavor_data() -- (B14, B15)
  G.withGame("vanilla", function()
    A.eq(H.lookup("C_AuctionHouse.SendBrowseQuery"), nil)
  end)
  G.withGame("retail", function()
    A.eq(H.lookup("QueryAuctionItems"), nil)
  end)
  G.withGame("mists", function()
    A.same({ type(_G.QueryAuctionItems), type(_G.C_AuctionHouse.SendBrowseQuery) }, { "function", "function" })
  end)
end

local function test_legacy_client_flag_by_flavor_assumed() -- (B1, B2, B15)
  for flavor, expected in pairs({ vanilla = true, tbc = true, mists = false }) do
    G.withGame(flavor, function(w)
      A.eq(_G.IsUsingLegacyAuctionClient(), expected, flavor)
      w:setMock({ auction = { legacy = not expected } })
      A.eq(_G.IsUsingLegacyAuctionClient(), not expected, flavor)
    end)
  end
  G.withGame("retail", function()
    A.eq(H.lookup("IsUsingLegacyAuctionClient"), nil)
  end)
end

return function()
  test_query_records_and_results_arrive_with_the_scenario()
  test_auction_item_tuple_and_time_left()
  test_a_row_without_a_name_reads_the_item_store()
  test_bids_record_only_and_the_query_gate_follows_the_store()
  test_families_follow_the_flavor_data()
  test_legacy_client_flag_by_flavor_assumed()
end
