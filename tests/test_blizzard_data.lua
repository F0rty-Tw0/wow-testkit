-- Window data (blizzard_data.lua, game/requests.lua, Client.db2Index): what the extract's DB2 tables fill into the
-- scenario stores without overwriting scenario data, the per-key index, and the record of server-bound calls. Every
-- extract is a kit-authored mini one (tests/helpers/windows.lua).
local A = require("assert")
local BlizzardData = require("blizzard_data")
local Client = require("client")
local Requests = require("game.requests")
local W = require("tests.helpers.windows")

local DB2 = {
  itemsparse = "return { [900100] = { Display_lang = 'Kit Hydrated', OverallQualityID = 2, ItemLevel = 10, Stackable = 20 } }",
  item = "return { [900100] = { ClassID = 7, SubclassID = 5, IconFileDataID = 132903 } }",
  spellname = "return { [9001] = { Name_lang = 'Kit Strike' } }",
  spellmisc = "return { [9001] = { SpellID = 9001, SpellIconFileDataID = 132292 } }", -- keyed by SpellID (db2_export.py:23)
}

local function test_items_copy_db2_rows_into_the_item_store()
  W.withWindows("vanilla", { db2 = DB2 }, function(w)
    BlizzardData.items(w, { 900100, 1 })
    A.same(w.mock.items[900100], { name = "Kit Hydrated", quality = 2, itemLevel = 10, stackCount = 20, icon = 132903, classID = 7, subClassID = 5 })
    A.eq(w.mock.items[1], nil)
    A.eq(_G.C_Item.GetItemInfo(900100), "Kit Hydrated") -- Task 7.4's reader, unchanged
  end)
end

local function test_scenario_item_data_wins_over_db2()
  W.withWindows("vanilla", { db2 = DB2 }, function(w)
    w:setMock({ items = { [900100] = { name = "Scenario Name" } } })
    BlizzardData.items(w, { 900100 })
    A.eq(w.mock.items[900100].name, "Scenario Name")
  end)
end

local function test_spells_copy_name_and_icon()
  W.withWindows("retail", { db2 = DB2 }, function(w)
    BlizzardData.spells(w, { 9001 })
    A.same({ _G.C_Spell.GetSpellInfo(9001).name, (_G.C_Spell.GetSpellTexture(9001)) }, { "Kit Strike", 132292 })
  end)
end

local function test_fill_merges_without_overwriting_and_no_extract_is_a_noop()
  W.withWindows("retail", { db2 = DB2 }, function(w)
    w:setMock({ kitFill = { canRepair = true } })
    A.eq(
      BlizzardData.fill(w, "kitFill", function()
        return { canRepair = false, repairCost = 7 }
      end),
      true
    )
    A.same({ w.mock.kitFill.canRepair, w.mock.kitFill.repairCost }, { true, 7 })
  end)
  W.withWindows("retail", {}, function(w) -- no extract
    A.same({
      BlizzardData.fill(w, "kitFill", function()
        return { repairCost = 9 }
      end),
      w.mock.kitFill,
    }, { false, nil })
  end)
end

-- (C1)
local function test_rows_by_reads_the_index_and_never_scans()
  local db2 = { talent = "return { [5] = { TabID = 3 }, [6] = { TabID = 4 }, [7] = { TabID = 3 } }" }
  local index = { ["talent.tabid"] = "return { [3] = { 5, 7 }, [4] = { 6 } }" } -- db2/index/talent.tabid.lua
  W.withWindows("retail", { db2 = db2, index = index }, function(w)
    A.same(Client.db2Index(w.client, "Talent", "TabID")[3], { 5, 7 })
    A.same({ #BlizzardData.rowsBy(w, "Talent", "TabID", 3), BlizzardData.rowsBy(w, "Talent", "TabID", 3)[2].TabID }, { 2, 3 })
    A.same(BlizzardData.rowsBy(w, "Talent", "ClassMask", 1), {}) -- no index file: empty, not a scan
    A.eq(Client.db2Index(w.client, "Talent", "ClassMask"), nil)
  end)
  W.withWindows("retail", {}, function(w) -- no extract
    A.same(BlizzardData.rowsBy(w, "Talent", "TabID", 3), {})
  end)
end

-- (B13)
local function test_requests_record_in_call_order_with_trailing_nils()
  W.withWindows("retail", {}, function(w)
    Requests.record(w, "BuyMerchantItem", 2, nil)
    A.same(w.mock.requests, { { api = "BuyMerchantItem", args = { 2, n = 2 } } })
  end)
end

return function()
  test_items_copy_db2_rows_into_the_item_store()
  test_scenario_item_data_wins_over_db2()
  test_spells_copy_name_and_icon()
  test_fill_merges_without_overwriting_and_no_extract_is_a_noop()
  test_rows_by_reads_the_index_and_never_scans()
  test_requests_record_in_call_order_with_trailing_nils()
end
