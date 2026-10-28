-- The transmog APIs (all five flavors' data; a window on retail, forever and mists): categories, appearances, sources and
-- outfits the scenario supplies, read back at call time (B16), and the open and close hooks. The collected flags are the
-- server's, so only the scenario sets them.
local A = require("assert")
local W = require("tests.helpers.windows")

local TM = {
  categories = { [1] = { name = "Kit Head" } },
  appearances = { [1] = { { visualID = 501, isCollected = true, uiOrder = 1 }, { visualID = 502, uiOrder = 2 } } },
  sources = { [501] = { 601 }, [502] = { 602 } },
  sourceInfo = {
    [601] = { visualID = 501, itemID = 900200, categoryID = 1, isCollected = true },
    [602] = { visualID = 502, itemID = 900201, categoryID = 1 },
  },
  outfits = { { outfitID = 1, name = "Kit Outfit" } },
  activeOutfitID = 1,
}

local function test_category_info_appearances_and_counts() -- (B16)
  W.withWindows("retail", {}, function(w)
    w:setMock({ transmog = TM })
    -- name, isWeapon, canHaveIllusions, canMainHand, canOffHand, canRanged (api/retail/TransmogItems.lua:458)
    A.same({ _G.C_TransmogCollection.GetCategoryInfo(1) }, { "Kit Head", false, false, false, false, false })
    A.eq(_G.C_TransmogCollection.GetCategoryInfo(9), nil)
    local list = _G.C_TransmogCollection.GetCategoryAppearances(1)
    A.same({ #list, list[2].isCollected, list[2].isUsable, list[2].canDisplayOnPlayer }, { 2, false, true, true })
    A.same({ list[1].visualID, list[1].isCollected, list[1].isFavorite, list[1].hasRequiredHoliday }, { 501, true, false, false })
    A.same({ _G.C_TransmogCollection.GetCategoryCollectedCount(1), _G.C_TransmogCollection.GetCategoryTotal(1) }, { 1, 2 })
    A.same({ _G.C_TransmogCollection.GetCategoryCollectedCount(9), _G.C_TransmogCollection.GetCategoryTotal(9) }, { 0, 0 })
  end)
end

local function test_sources_and_has_transmog() -- (B16)
  W.withWindows("retail", {}, function(w)
    w:setMock({ transmog = TM })
    A.same({ _G.C_TransmogCollection.GetSourceInfo(601).itemID, _G.C_Transmog.GetItemIDForSource(602) }, { 900200, 900201 })
    local info = _G.C_TransmogCollection.GetSourceInfo(602)
    A.same({ info.sourceID, info.visualID, info.itemModID, info.categoryID, info.isCollected }, { 602, 502, 0, 1, false })
    A.eq(_G.C_TransmogCollection.GetSourceInfo(1), nil)
    A.same(_G.C_TransmogCollection.GetAllAppearanceSources(501), { 601 })
    A.same(_G.C_TransmogCollection.GetAllAppearanceSources(1), {})
    A.eq(_G.C_TransmogCollection.GetAppearanceSources(501)[1].sourceID, 601)
    A.same({ _G.C_TransmogCollection.PlayerHasTransmog(900200), _G.C_TransmogCollection.PlayerHasTransmog(900201) }, { true, false })
    A.eq(_G.C_TransmogCollection.PlayerHasTransmog(900200, 1), false) -- another modifier
  end)
end

local function test_outfits_and_active_outfit() -- (B16)
  W.withWindows("retail", {}, function(w)
    w:setMock({ transmog = TM })
    local outfit = _G.C_TransmogOutfitInfo.GetOutfitsInfo()[1]
    A.same({ outfit.name, outfit.outfitID, outfit.isDisabled, outfit.playerFacingOutfitIndex }, { "Kit Outfit", 1, false, 1 })
    A.eq(_G.C_TransmogOutfitInfo.GetActiveOutfitID(), 1)
    _G.C_TransmogOutfitInfo.CommitAndApplyAllPending(true)
    A.same({ w.mock.requests[1].api, w.mock.requests[1].args }, { "C_TransmogOutfitInfo.CommitAndApplyAllPending", { n = 1, true } })
  end)
end

local function test_viewed_slot_is_the_scenarios_record_by_slot_type_and_option() -- (B16)
  W.withWindows("retail", {}, function(w)
    w:setMock({ transmog = { slots = { ["1:0:0"] = { transmogID = 501, isTransmogrified = true } } } })
    A.eq(_G.C_TransmogOutfitInfo.GetViewedOutfitSlotInfo(1, 0, 0).transmogID, 501)
    A.eq(_G.C_TransmogOutfitInfo.GetViewedOutfitSlotInfo(1, 1, 0), nil)
  end)
end

local function test_apis_answer_on_tbc_but_the_window_does_not_exist() -- (B1, B16)
  W.scenario("tbc", {}, function(s)
    s.w:setMock({ transmog = TM })
    A.eq((_G.C_TransmogCollection.GetCategoryInfo(1)), "Kit Head")
    local ok, err = pcall(s.openWindow, s, "transmog", TM)
    A.same({ ok, err:match("unknown window 'transmog'") ~= nil }, { false, true })
  end)
end

-- (B16, confirmed: argument `category`, api/retail/TransmogItems.lua:388; the location is ignored, assumed)
local function test_appearances_take_a_category_and_an_ignored_location()
  W.withWindows("retail", {}, function(w)
    w:setMock({ transmog = TM })
    A.eq(#_G.C_TransmogCollection.GetCategoryAppearances(1, nil), 2) -- the second argument, transmogLocation, is optional and ignored
    A.eq(#_G.C_TransmogCollection.GetCategoryAppearances(1, {}), 2)
  end)
end

return function()
  test_category_info_appearances_and_counts()
  test_sources_and_has_transmog()
  test_outfits_and_active_outfit()
  test_viewed_slot_is_the_scenarios_record_by_slot_type_and_option()
  test_apis_answer_on_tbc_but_the_window_does_not_exist()
  test_appearances_take_a_category_and_an_ignored_location()
end
