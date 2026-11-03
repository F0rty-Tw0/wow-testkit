-- Sim loot items: the default table drops the real Broken Fang and Linen Cloth when the extract has both, else the kit
-- items. The extract is a kit-authored mini one; the suite never reads a client.
local A = require("assert")
local H = require("tests.helpers.client")
local LH = require("tests.helpers.sim_loot")
local Scenario = require("scenario")
local SH = require("tests.helpers.sim_combat")
local SimLoot = require("sim_loot")
local SimTarget = require("sim_target")
local Tmp = require("tests.helpers.tmp")

local R = SimLoot.REAL

local ITEM = 'return { [7073] = { Display_lang = "Fake Fang", OverallQualityID = 0, ItemLevel = 1, Stackable = 20 },'
  .. ' [2589] = { Display_lang = "Fake Linen", OverallQualityID = 1, ItemLevel = 1, Stackable = 20 } }'
local ONLY_FANG = 'return { [7073] = { Display_lang = "Fake Fang", OverallQualityID = 0 } }'

local function withExtract(flavor, sparse, fn)
  local client = H.extract(Tmp.dir("loot"), flavor, "1", { ["db2/itemsparse.lua"] = sparse })
  local s = Scenario.new({ addon = "T", root = "T", flavor = flavor, client = client, sim = {} })
  local ok, err = pcall(fn, s.w)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function test_the_real_items_resolve_from_the_extract(w)
  A.same({ R.gray, R.white }, { 7073, 2589 })
  A.same(SimLoot.defaultItems(w), R)
  local mob = LH.corpse(w, 0, -8)
  A.same(LH.dropList(mob), { "money:37", "item:7073x1", "item:2589x2" })
  SimTarget.interact(w, mob, "RightButton")
  A.eq(select(2, _G.GetLootSlotInfo(2)), "Fake Fang")
  A.eq(w.sim.loot.items, SimLoot.defaultItems(w)) -- cached
end

local function test_one_missing_record_falls_back_to_the_kit(w)
  A.same(SimLoot.defaultItems(w), SimLoot.KIT)
  A.same(LH.dropList(LH.corpse(w, 0, -8)), { "money:37", "item:900201x1", "item:900202x2" })
end

local function test_no_extract_uses_the_kit(w)
  A.same(SimLoot.defaultItems(w), SimLoot.KIT)
end

local function main()
  for _, flavor in ipairs(LH.FLAVORS) do
    withExtract(flavor, ITEM, test_the_real_items_resolve_from_the_extract)
    withExtract(flavor, ONLY_FANG, test_one_missing_record_falls_back_to_the_kit)
    SH.withSim(flavor, test_no_extract_uses_the_kit)
  end
end

main()
