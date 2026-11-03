-- Sim loot taking: LootSlot on an item and on the coin, the events in the ruled order, the chat lines and the auto close.
local A = require("assert")
local LH = require("tests.helpers.sim_loot")
local SH = require("tests.helpers.sim_combat")
local SimLoot = require("sim_loot")

local K = SimLoot.KIT

local function openDefault(w)
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)

  return mob
end

local function test_an_item_slot_fires_the_ruled_order(w)
  openDefault(w)
  local ev = SH.record(w, LH.LOOT_EVENTS)
  _G.LootSlot(2)
  A.same(LH.names(ev), { "ITEM_PUSH", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "CHAT_MSG_LOOT", "LOOT_SLOT_CLEARED" })
end

local function test_an_item_slot_names_the_bag_the_icon_and_the_slot(w)
  openDefault(w)
  local ev = SH.record(w, LH.LOOT_EVENTS)
  _G.LootSlot(2)
  A.same({ ev[1][3], ev[1][4], ev[2][3], ev[5][3] }, { 0, 900201, 0, 2 })
end

local function test_an_item_slot_writes_the_loot_line(w)
  openDefault(w)
  local ev = SH.record(w, { "CHAT_MSG_LOOT" })
  _G.LootSlot(2)
  A.eq(ev[1][3], string.format(_G.LOOT_ITEM_SELF, _G.C_Container.GetContainerItemLink(0, 1)))
end

local function test_a_multi_count_item_names_the_count(w)
  local ev = SH.record(w, { "CHAT_MSG_LOOT" })
  SimLoot.open(w, LH.corpse(w, 0, -8, { money = 0, items = { { itemID = K.white, count = 2 } } }))
  _G.LootSlot(1)
  A.eq(ev[1][3], string.format(_G.LOOT_ITEM_SELF_MULTIPLE, _G.C_Container.GetContainerItemLink(0, 1), 2))
end

local function test_taken_items_fill_the_bags_in_order(w)
  openDefault(w)
  _G.LootSlot(2)
  _G.LootSlot(3)
  A.same({ _G.C_Container.GetContainerItemID(0, 1), _G.C_Container.GetContainerItemInfo(0, 2).stackCount }, { K.gray, 2 })
end

local function test_the_last_slot_closes_the_window(w)
  local mob = openDefault(w)
  local ev = SH.record(w, LH.LOOT_EVENTS)
  _G.LootSlot(1)
  _G.LootSlot(2)
  _G.LootSlot(3)
  A.eq(ev[#ev].event, "LOOT_CLOSED")
  A.same({ mob.lootable, w.sim.loot.window, _G.GetNumLootItems() }, { false, nil, 0 })
  A.eq(#w.warnings, 0)
end

local function test_the_coin_slot_fires_money_then_chat(w)
  local ev = SH.record(w, LH.LOOT_EVENTS)
  SimLoot.open(w, LH.corpse(w, 0, -8, { money = 37, items = { { itemID = K.white } } }))
  _G.LootSlot(1)
  A.same(LH.from(LH.names(ev), "PLAYER_MONEY"), { "PLAYER_MONEY", "CHAT_MSG_MONEY", "LOOT_SLOT_CLEARED" })
end

local function test_the_coin_slot_adds_the_copper(w)
  openDefault(w)
  _G.LootSlot(1)
  A.eq(_G.GetMoney(), 37)
end

local function test_a_copper_only_coin_line(w)
  local ev = SH.record(w, { "CHAT_MSG_MONEY" })
  SimLoot.open(w, LH.corpse(w, 0, -8, { money = 37 }))
  _G.LootSlot(1)
  A.eq(ev[1][3], string.format(_G.YOU_LOOT_MONEY, string.format(_G.COPPER_AMOUNT, 37)))
end

local function test_a_coin_line_names_gold_silver_and_copper(w)
  local ev = SH.record(w, { "CHAT_MSG_MONEY" })
  SimLoot.open(w, LH.corpse(w, 0, -8, { money = 12345 }))
  _G.LootSlot(1)
  local coins = table.concat({
    string.format(_G.GOLD_AMOUNT, 1),
    string.format(_G.SILVER_AMOUNT, 23),
    string.format(_G.COPPER_AMOUNT, 45),
  }, ", ")
  A.eq(ev[1][3], string.format(_G.YOU_LOOT_MONEY, coins))
end

local function test_chat_line_carries_the_player(w, _, player)
  local ev = SH.record(w, { "CHAT_MSG_MONEY" })
  SimLoot.open(w, LH.corpse(w, 0, -8, { money = 5 }))
  _G.LootSlot(1)
  local line = ev[1]
  A.same({ line[4], line[14], line[15] }, { player.name, player.guid, 0 })
  A.same({ line[13], w.sim.loot.line }, { 1, 1 })
end

return function()
  for _, flavor in ipairs(LH.FLAVORS) do
    local tests = {
      test_an_item_slot_fires_the_ruled_order,
      test_an_item_slot_names_the_bag_the_icon_and_the_slot,
      test_an_item_slot_writes_the_loot_line,
      test_a_multi_count_item_names_the_count,
      test_taken_items_fill_the_bags_in_order,
      test_the_last_slot_closes_the_window,
      test_the_coin_slot_fires_money_then_chat,
      test_the_coin_slot_adds_the_copper,
      test_a_copper_only_coin_line,
      test_a_coin_line_names_gold_silver_and_copper,
      test_chat_line_carries_the_player,
    }
    for _, t in ipairs(tests) do
      SH.withSim(flavor, t)
    end
  end
end
