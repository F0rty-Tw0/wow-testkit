-- Transmog sources built from the extract's ItemModifiedAppearance and ItemAppearance tables (game/transmog_db2.lua):
-- scenario data wins and the collected flags stay the scenario's. Every table is kit-authored (tests/helpers/windows.lua),
-- never a Blizzard row.
local A = require("assert")
local BlizzardData = require("blizzard_data")
local TransmogDb2 = require("game.transmog_db2")
local W = require("tests.helpers.windows")

local OPTS = {
  db2 = {
    itemmodifiedappearance = [[return {
      [7001] = { ID = 7001, ItemID = 900200, ItemAppearanceModifierID = 0, ItemAppearanceID = 501 },
      [7002] = { ID = 7002, ItemID = 900201, ItemAppearanceModifierID = 3, ItemAppearanceID = 502 },
    }]],
    itemappearance = "return { [501] = { ID = 501, DefaultIconFileDataID = 135001 }, [502] = { ID = 502, DefaultIconFileDataID = 135002 } }",
  },
  index = { ["itemmodifiedappearance.itemid"] = "return { [900200] = { 7001 }, [900201] = { 7002 } }" },
}

local function fill(w, ids)
  return BlizzardData.fill(w, "transmog", function()
    return TransmogDb2.sources(w, ids)
  end)
end

local function test_sources_build_from_item_modified_appearance()
  W.withWindows("retail", OPTS, function(w)
    A.eq(fill(w, { 900200, 900201 }), true)
    local info = _G.C_TransmogCollection.GetSourceInfo(7001)
    A.same({ info.sourceID, info.visualID, info.itemID, info.itemModID }, { 7001, 501, 900200, 0 })
    A.same(_G.C_TransmogCollection.GetAllAppearanceSources(501), { 7001 })
    A.same({ _G.C_TransmogCollection.GetSourceInfo(7002).itemModID, _G.C_Transmog.GetItemIDForSource(7002) }, { 3, 900201 })
  end)
end

local function test_no_extract_builds_nothing()
  W.withWindows("retail", {}, function(w)
    A.eq(TransmogDb2.sources(w, { 900200 }), nil)
    A.eq(fill(w, { 900200 }), false)
  end)
end

local function test_collected_flags_stay_scenario_data_assumed() -- (B16)
  W.withWindows("retail", OPTS, function(w)
    w:setMock({ transmog = { sourceInfo = { [7002] = { isCollected = true } } } })
    fill(w, { 900200, 900201 })
    A.same({ _G.C_TransmogCollection.GetSourceInfo(7001).isCollected, _G.C_TransmogCollection.GetSourceInfo(7002).isCollected }, { false, true })
    A.eq(_G.C_TransmogCollection.GetSourceInfo(7002).visualID, 502) -- the DB2 fields fill around the scenario's
  end)
end

local function test_icon_fills_the_item_store_only_when_absent()
  W.withWindows("retail", OPTS, function(w)
    w:setMock({ items = { [900200] = { name = "Kit Helm", icon = 1 }, [900201] = { name = "Kit Cap" } } })
    fill(w, { 900200, 900201 })
    A.same({ w.mock.items[900200].icon, w.mock.items[900201].icon, w.mock.items[900201].name }, { 1, 135002, "Kit Cap" })
  end)
end

return function()
  test_sources_build_from_item_modified_appearance()
  test_no_extract_builds_nothing()
  test_collected_flags_stay_scenario_data_assumed()
  test_icon_fills_the_item_store_only_when_absent()
end
