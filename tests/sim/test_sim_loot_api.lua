-- Sim loot reads: the Blizzard-named loot API over the open window, one API per test.
local A = require("assert")
local LH = require("tests.helpers.sim_loot")
local SH = require("tests.helpers.sim_combat")
local SimLoot = require("sim_loot")
local SimMobs = require("sim_mobs")

local UNKNOWN_GUID = "Creature-0-0-0-0-1-0"

local function openDefault(w)
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)

  return mob
end

local function test_a_closed_window_has_no_slots(w)
  LH.corpse(w, 0, -8)
  A.eq(_G.GetNumLootItems(), 0)
end

local function test_an_open_window_counts_its_slots(w)
  openDefault(w)
  A.eq(_G.GetNumLootItems(), 3)
end

local function test_the_coin_slot_info(w)
  openDefault(w)
  local tex, name, qty, cur, quality, locked, quest, qid, active, coin = _G.GetLootSlotInfo(1)
  A.same(
    { name, qty, coin, tex, quality, locked, quest, active },
    { string.format(_G.COPPER_AMOUNT, 37), 0, true, "Interface\\Icons\\INV_Misc_Coin_01", 0, false, false, false }
  )
  A.same({ cur, qid }, {}) -- no currency id and no quest id
end

local function test_an_item_slot_info(w)
  openDefault(w)
  local _, name, qty, _, quality = _G.GetLootSlotInfo(2)
  A.same({ name, qty, quality }, { "Kit Scrap", 1, 0 })
end

local function test_slot_types(w)
  openDefault(w)
  local types = { _G.GetLootSlotType(1), _G.GetLootSlotType(2), _G.GetLootSlotType(9) }
  A.same(types, { _G.Enum.LootSlotType.Money, _G.Enum.LootSlotType.Item, _G.Enum.LootSlotType.None })
end

local function test_only_an_item_slot_has_a_link(w)
  openDefault(w)
  local link = _G.GetLootSlotLink(2)
  A.same({ _G.GetLootSlotLink(1), link:find("Hitem:900201:", 1, true) ~= nil }, { nil, true })
end

local function test_a_slot_has_an_item_until_taken(w)
  openDefault(w)
  local before = _G.LootSlotHasItem(2)
  _G.LootSlot(2)
  A.same({ before, _G.LootSlotHasItem(2) }, { true, false })
end

local function test_can_loot_a_near_corpse(w)
  local near = LH.corpse(w, 0, -8)
  A.same({ _G.CanLootUnit(near.guid) }, { true, true })
end

local function test_a_far_corpse_has_loot_but_cannot_be_looted(w)
  local far = LH.corpse(w, 0, 30)
  A.same({ _G.CanLootUnit(far.guid) }, { true, false })
end

local function test_a_living_mob_has_no_loot(w)
  local alive = SimMobs.spawn(w, { pos = { x = 5, y = -8 } })
  A.same({ _G.CanLootUnit(alive.guid) }, { false, false })
end

local function test_an_unknown_guid_has_no_loot(_)
  A.same({ _G.CanLootUnit(UNKNOWN_GUID) }, { false, false })
end

local function test_loot_source_is_the_corpse(w)
  local mob = openDefault(w)
  A.same({ _G.GetLootSourceInfo(2) }, { mob.guid, 1 })
end

local function test_loot_info_lists_the_open_slots(w)
  openDefault(w)
  local info = _G.GetLootInfo()
  A.same({ #info, info[2].item, info[2].quantity, info[2].quality }, { 3, "Kit Scrap", 1, 0 })
end

local function test_confirm_loot_slot_is_only_recorded(w)
  openDefault(w)
  _G.ConfirmLootSlot(2)
  A.same({ w.mock.requests[#w.mock.requests].api, _G.LootSlotHasItem(2) }, { "ConfirmLootSlot", true })
end

local function test_close_loot_empties_the_reads(w)
  openDefault(w)
  _G.CloseLoot()
  A.same({ _G.GetLootInfo(), _G.GetLootSlotInfo(1), _G.LootSlotHasItem(1) }, { {}, nil, false })
end

local function test_fishing_loot_is_off(_)
  A.eq(_G.IsFishingLoot(), false)
end

local function test_the_loot_threshold_is_uncommon(_)
  A.eq(_G.GetLootThreshold(), 2)
end

local function test_legacy_loot_mode_is_off(_)
  A.eq(_G.C_Loot.IsLegacyLootModeEnabled(), false)
end

return function()
  for _, flavor in ipairs(LH.FLAVORS) do
    local tests = {
      test_a_closed_window_has_no_slots,
      test_an_open_window_counts_its_slots,
      test_the_coin_slot_info,
      test_an_item_slot_info,
      test_slot_types,
      test_only_an_item_slot_has_a_link,
      test_a_slot_has_an_item_until_taken,
      test_can_loot_a_near_corpse,
      test_a_far_corpse_has_loot_but_cannot_be_looted,
      test_a_living_mob_has_no_loot,
      test_an_unknown_guid_has_no_loot,
      test_loot_source_is_the_corpse,
      test_loot_info_lists_the_open_slots,
      test_confirm_loot_slot_is_only_recorded,
      test_close_loot_empties_the_reads,
      test_fishing_loot_is_off,
      test_the_loot_threshold_is_uncommon,
      test_legacy_loot_mode_is_off,
    }
    for _, t in ipairs(tests) do
      SH.withSim(flavor, t)
    end
  end
end
