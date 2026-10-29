-- The auction house window (Task 12.6): the opener writes the result store and the window reads it back through the
-- modern API. The plan lists this test in test_blizzard_windows.lua, which is at its 300-line limit, so it lives here. The
-- extract is a kit-authored mini one (tests/helpers/windows.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local W = require("tests.helpers.windows")

local SPEC = { auction = { addon = "Blizzard_MiniAuction", open = "AUCTION_HOUSE_SHOW", frame = "MiniAuctionFrame" } }
local KEY = { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
local MODERN = { browse = { { itemKey = KEY, totalQuantity = 40, minPrice = 20, containsOwnerItem = false } } }

local function test_auction_window_lists_browse_results()
  B.run(B.mini({ blizzard_miniauction = W.MINI.blizzard_miniauction }), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = SPEC
      s.w:setMock({ items = { [2589] = { name = "Kit Cloth", quality = 1, icon = 132903 } } })
    end,
  }, function(s)
    s:openWindow("auction", MODERN)
    A.same({ _G.MiniAuctionFrame:IsShown(), _G.MiniAuctionFrame.Row:GetText() }, { true, "Kit Cloth" })
    s:closeWindow("auction")
    A.eq(#_G.C_AuctionHouse.GetBrowseResults(), 1) -- closing keeps the store
  end)
end

-- (BU21, assumed) the classic UIParent calls AuctionFrame_Show on AUCTION_HOUSE_SHOW (tbc uiparent.lua:789-793) and the layer
-- never wires it, so the kit calls the global once Blizzard_AuctionUI is loaded.
local CLASSIC_AUCTION = {
  blizzard_auctionui = {
    toc = "## Interface: 20506\n## LoadOnDemand: 1\nAuctionUI.lua\n",
    files = { ["auctionui.lua"] = "function AuctionFrame_Show() AuctionShownBy = 'show-global' end" },
  },
}
local function test_classic_auction_opens_through_its_show_global_assumed()
  for _, flavor in ipairs({ "tbc", "vanilla" }) do
    B.run(B.mini(CLASSIC_AUCTION), { flavor = flavor, header = "Interface-TBC: 20506", targets = { "Blizzard_MiniBase" } }, function(s)
      s:openWindow("auction", {})
      A.eq(_G.AuctionShownBy, "show-global", flavor)
    end)
  end
end

return function()
  test_auction_window_lists_browse_results()
  test_classic_auction_opens_through_its_show_global_assumed()
end
