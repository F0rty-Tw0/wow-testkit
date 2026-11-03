-- Sim loot edges: a full or partial bag, the idempotent close, renumbering, walking away, switching corpses, reset,
-- autoloot and the reload.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.session")
local LH = require("tests.helpers.sim_loot")
local SH = require("tests.helpers.sim_combat")
local Sim = require("sim")
local SimBags = require("sim_bags")
local SimLoot = require("sim_loot")

local K = SimLoot.KIT

-- Review Focus 4: a full bag with a partial stack of the drop's item (19 of 20 in the only slot), the window open on a
-- corpse that drops 2 of it.
local function openPartialFit(w)
  LH.items(w)
  SimBags.setSize(w, 0, 1)
  SimBags.add(w, K.white, 19)
  local mob = LH.corpse(w, 0, -8, { money = 0, items = { { itemID = K.white, count = 2 } } })
  SimLoot.open(w, mob)

  return mob
end

local PARTIAL_EVENTS = { "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "CHAT_MSG_LOOT", "UI_ERROR_MESSAGE", "ITEM_PUSH" }

local function test_a_partial_fit_tops_the_stack_up_and_the_rest_stays(w)
  openPartialFit(w)
  _G.LootSlot(1)
  A.same({ _G.C_Container.GetContainerItemInfo(0, 1).stackCount, (select(3, _G.GetLootSlotInfo(1))) }, { 20, 1 })
end

local function test_a_partial_fit_fires_changed_then_the_error(w)
  openPartialFit(w)
  local ev = SH.record(w, PARTIAL_EVENTS)
  _G.LootSlot(1)
  A.same(LH.names(ev), { "ITEM_PUSH", "CHAT_MSG_LOOT", "LOOT_SLOT_CHANGED", "UI_ERROR_MESSAGE" })
  A.same({ ev[3][3], ev[4][4] }, { 1, _G.ERR_INV_FULL })
end

local function test_a_partial_fit_names_the_placed_count(w)
  openPartialFit(w)
  local ev = SH.record(w, { "CHAT_MSG_LOOT" })
  _G.LootSlot(1)
  A.eq(ev[1][3], string.format(_G.LOOT_ITEM_SELF, _G.C_Container.GetContainerItemLink(0, 1))) -- one placed
end

local function test_nothing_fits_fires_the_error_alone(w)
  openPartialFit(w)
  _G.LootSlot(1)
  local ev = SH.record(w, PARTIAL_EVENTS)
  _G.LootSlot(1)
  A.same(LH.names(ev), { "UI_ERROR_MESSAGE" })
end

local function test_the_rest_loots_once_a_slot_frees(w)
  local mob = openPartialFit(w)
  _G.LootSlot(1)
  local ev = SH.record(w, PARTIAL_EVENTS)
  SimBags.setSize(w, 0, 2)
  _G.LootSlot(1)
  A.same({ ev[#ev].event, mob.lootable }, { "LOOT_CLOSED", false })
end

local function test_close_twice_fires_once(w)
  local ev = SH.record(w, { "LOOT_CLOSED" })
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)
  _G.CloseLoot()
  _G.CloseLoot()
  A.same({ #ev, mob.lootable, #mob.drops, w.sim.loot.window }, { 1, true, 3, nil })
end

local function test_a_close_from_the_closed_handler_does_nothing(w)
  local ev = SH.record(w, { "LOOT_CLOSED" })
  local frame = _G.CreateFrame("Frame")
  frame:RegisterEvent("LOOT_CLOSED")
  frame:SetScript("OnEvent", function()
    _G.CloseLoot() -- Blizzard's LootFrame hides on LOOT_CLOSED and its OnHide calls CloseLoot
  end)
  SimLoot.open(w, LH.corpse(w, 0, -8))
  _G.CloseLoot()
  A.eq(#ev, 1)
end

local function test_a_close_from_an_item_event_handler_drops_the_taken_slot(w)
  local frame = _G.CreateFrame("Frame")
  frame:RegisterEvent("ITEM_PUSH")
  frame:SetScript("OnEvent", function()
    _G.CloseLoot()
  end)
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)
  _G.LootSlot(2)
  frame:UnregisterAllEvents()
  SimLoot.open(w, mob)
  A.same({ _G.GetNumLootItems(), _G.LootSlotHasItem(2) }, { 2, true })
end

local function test_reopen_renumbers_the_rest(w)
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)
  _G.LootSlot(2)
  _G.CloseLoot()
  SimLoot.open(w, mob)
  A.eq(_G.GetNumLootItems(), 2)
  A.eq(select(2, _G.GetLootSlotInfo(2)), "Kit Linen")
  A.same(LH.dropList(mob), { "money:37", "item:900202x2" })
end

local function test_walking_away_closes(w, s)
  local ev = SH.record(w, { "LOOT_CLOSED" })
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)
  s:place(0, -30)
  s:simStep(1 / 60)
  s:simStep(1 / 60)
  A.same({ #ev, mob.lootable, w.sim.loot.window }, { 1, true, nil })
end

local function test_despawn_closes(w)
  local ev = SH.record(w, { "LOOT_CLOSED" })
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)
  Actors.remove(w, mob)
  A.same({ #ev, w.sim.loot.window }, { 1, nil })
  A.eq(w.sim.loot.corpses[mob.guid], nil)
end

local function test_switching_corpses(w)
  local ev = SH.record(w, { "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED" })
  local a, b = LH.corpse(w, 0, -8), LH.corpse(w, 1, -8)
  SimLoot.open(w, a)
  SimLoot.open(w, a) -- already open: ignored
  A.same(LH.names(ev), { "LOOT_READY", "LOOT_OPENED" })
  SimLoot.open(w, b)
  A.same(LH.names(ev), { "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "LOOT_READY", "LOOT_OPENED" })
  A.eq(w.sim.loot.window.guid, b.guid)
end

local function test_reset_closes_and_empties_the_bags(w)
  SimLoot.open(w, LH.corpse(w, 0, -8))
  _G.LootSlot(2)
  local ev = SH.record(w, { "LOOT_CLOSED", "BAG_UPDATE", "BAG_UPDATE_DELAYED" })
  Sim.reset(w)
  A.same(LH.names(ev), { "LOOT_CLOSED", "BAG_UPDATE", "BAG_UPDATE_DELAYED" })
  A.same({ w.sim.loot.window, SimBags.freeSlots(w), w.sim.loot.seed }, { nil, 16, 1 })
end

local function test_autoloot_by_cvar(w)
  _G.SetCVar("autoLootDefault", "1")
  local ev = SH.record(w, { "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED" })
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)
  A.same(LH.names(ev), { "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" })
  A.same({ ev[1][3], mob.lootable, _G.GetMoney() }, { true, false, 37 })
end

local function test_the_toggle_key_turns_autoloot_on(w)
  local ev = SH.record(w, { "LOOT_OPENED" })
  w.mock.modifiers.shift = true -- cvar off + shift: auto
  SimLoot.open(w, LH.corpse(w, 0, -8))
  A.eq(ev[1][3], true)
end

local function test_the_toggle_key_turns_autoloot_off(w)
  local ev = SH.record(w, { "LOOT_OPENED" })
  w.mock.modifiers.shift = true
  _G.SetCVar("autoLootDefault", "1") -- cvar on + shift: manual
  local manual = LH.corpse(w, 0, -8)
  SimLoot.open(w, manual)
  A.same({ ev[1][3], manual.lootable }, { false, true })
end

local function test_autoloot_with_full_bags(w)
  LH.items(w)
  LH.fillBags(w, LH.SINGLE)
  _G.SetCVar("autoLootDefault", "1")
  local ev = SH.record(w, { "UI_ERROR_MESSAGE", "PLAYER_MONEY", "LOOT_CLOSED" })
  local mob = LH.corpse(w, 0, -8)
  SimLoot.open(w, mob)
  A.same(LH.names(ev), { "PLAYER_MONEY", "UI_ERROR_MESSAGE", "UI_ERROR_MESSAGE" })
  A.same({ ev[2][4], mob.lootable, w.sim.loot.window ~= nil, _G.GetMoney() }, { _G.ERR_INV_FULL, true, true, 37 })
  A.same(LH.dropList(mob), { "money:37", "item:900201x1", "item:900202x2" })
end

local function test_a_reload_keeps_the_rest_and_closes_the_window()
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    local w = sess.w
    local mob = LH.corpse(w, 0, -8, { money = 10, items = { { itemID = K.gray, chance = 0.5 }, { itemID = K.white } } })
    SimLoot.open(w, mob)
    _G.LootSlot(2)
    local seed = w.sim.loot.seed
    SH.reloaded(sess, function(fresh)
      local back = Actors.get(fresh.w, mob.guid)
      A.same({ _G.GetNumLootItems(), fresh.w.sim.loot.window, back.lootable }, { 0, nil, true })
      A.same(LH.dropList(back), { "money:10", "item:900202x1" })
      A.same({ _G.C_Container.GetContainerItemInfo(0, 1).itemID, fresh.w.sim.loot.seed }, { K.gray, seed })
      A.eq(#fresh.w.warnings, 0)
      A.eq(SimLoot.open(fresh.w, back), true) -- the corpse opens again
      A.eq(_G.GetNumLootItems(), 2)
    end)
  end)
end

return function()
  for _, flavor in ipairs(LH.FLAVORS) do
    local tests = {
      test_a_partial_fit_tops_the_stack_up_and_the_rest_stays,
      test_a_partial_fit_fires_changed_then_the_error,
      test_a_partial_fit_names_the_placed_count,
      test_nothing_fits_fires_the_error_alone,
      test_the_rest_loots_once_a_slot_frees,
      test_close_twice_fires_once,
      test_a_close_from_the_closed_handler_does_nothing,
      test_a_close_from_an_item_event_handler_drops_the_taken_slot,
      test_reopen_renumbers_the_rest,
      test_walking_away_closes,
      test_despawn_closes,
      test_switching_corpses,
      test_reset_closes_and_empties_the_bags,
      test_autoloot_by_cvar,
      test_the_toggle_key_turns_autoloot_on,
      test_the_toggle_key_turns_autoloot_off,
      test_autoloot_with_full_bags,
    }
    for _, t in ipairs(tests) do
      SH.withSim(flavor, t)
    end
  end
  test_a_reload_keeps_the_rest_and_closes_the_window()
end
