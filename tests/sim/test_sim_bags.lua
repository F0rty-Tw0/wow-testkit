-- Sim bags: the C_Container fakes over w.sim.bags, the stacking order of place, BAG_UPDATE events, and the reload.
local A = require("assert")
local H = require("tests.helpers.session")
local LH = require("tests.helpers.sim_loot")
local SH = require("tests.helpers.sim_combat")
local Sim = require("sim")
local SimBags = require("sim_bags")

local function test_empty_bags()
  A.same({ _G.C_Container.GetContainerNumSlots(0), _G.C_Container.GetContainerNumSlots(1) }, { 16, 0 })
  A.same({ _G.C_Container.GetContainerNumFreeSlots(0) }, { 16, 0 })
  A.eq(_G.C_Container.CalculateTotalNumberOfFreeBagSlots(), 16)
  A.eq(_G.C_Container.GetContainerItemInfo(0, 1), nil)
  A.same({ _G.C_Container.GetContainerNumSlots(9), _G.C_Container.GetContainerNumSlots("x") }, { 0, 0 })
  A.eq(_G.C_Container.ContainerIDToInventoryID(1), 20)
  A.same({ _G.C_Container.GetBagName(0), _G.C_Container.GetBagName(1) }, { "Backpack", nil })
end

local function test_add_stacks_and_reports(w)
  local ev = SH.record(w, { "BAG_UPDATE", "BAG_UPDATE_DELAYED" })
  A.same({ SimBags.add(w, LH.STACK, 7) }, { 7, 0, { 0 } })
  local info = _G.C_Container.GetContainerItemInfo(0, 1)
  A.same(
    { info.stackCount, info.itemID, info.itemName, info.quality, info.iconFileID, info.isLocked },
    { 5, LH.STACK, "Kit Stack", 1, 900301, false }
  )
  A.eq(info.hyperlink, string.format("|cffffffff|Hitem:%d::::::::::::|h[Kit Stack]|h|r", LH.STACK))
  A.eq(_G.C_Container.GetContainerItemInfo(0, 2).stackCount, 2)
  A.same({ SimBags.add(w, LH.STACK, 3) }, { 3, 0, { 0 } }) -- tops slot 2 up first
  A.eq(_G.C_Container.GetContainerItemInfo(0, 2).stackCount, 5)
  A.eq(_G.C_Container.GetContainerItemInfo(0, 3), nil)
  A.same(
    { ev[1].event, ev[1][3], ev[2].event, ev[3].event, ev[3][3], ev[4].event },
    { "BAG_UPDATE", 0, "BAG_UPDATE_DELAYED", "BAG_UPDATE", 0, "BAG_UPDATE_DELAYED" }
  )
  A.eq(#w.warnings, 0)
end

local function test_a_second_bag_adds_its_slots(w)
  SimBags.setSize(w, 1, 2)
  A.same({ SimBags.freeSlots(w), _G.C_Container.GetBagName(1) }, { 18, "Kit Bag 1" })
end

local function test_full_bags_take_nothing(w)
  SimBags.setSize(w, 1, 2)
  A.eq(LH.fillBags(w, LH.SINGLE), 18)
  A.same({ SimBags.add(w, LH.SINGLE, 2) }, { 0, 2, {} }) -- nothing placed, nothing touched
  A.same({ SimBags.place(w, LH.STACK, 1) }, { 0, 1, {} })
end

local function test_full_bags_report_no_free_slot(w)
  SimBags.setSize(w, 1, 2)
  LH.fillBags(w, LH.SINGLE)
  A.same({ _G.C_Container.GetContainerNumFreeSlots(0) }, { 0, 0 })
  A.same(_G.C_Container.GetContainerFreeSlots(1), {})
  A.eq(_G.C_Container.HasContainerItem(1, 2), true)
end

local function test_fill_order_spans_bags(w)
  SimBags.setSize(w, 1, 2)
  LH.fillBags(w, LH.SINGLE)
  A.same({ SimBags.add(w, LH.STACK, 1) }, { 0, 1, {} })
  A.eq(_G.C_Container.GetContainerItemLink(1, 2) ~= nil, true)
  A.eq(_G.C_Container.GetContainerItemID(1, 2), LH.SINGLE)
end

local function test_overflow_goes_to_the_next_bag(w)
  SimBags.setSize(w, 1, 2)
  LH.fillBags(w, LH.SINGLE)
  SimBags.clear(w)
  A.eq(LH.fillBags(w, LH.STACK), 18)
  A.same({ SimBags.place(w, LH.STACK, 1) }, { 0, 1, {} })
  SimBags.setSize(w, 2, 1)
  A.same({ SimBags.place(w, LH.STACK, 7) }, { 5, 2, { 2 } })
  A.eq(_G.C_Container.GetContainerItemInfo(2, 1).stackCount, 5)
end

local function test_set_size_refuses_to_drop_items(w)
  LH.fillBags(w, LH.SINGLE)
  A.errors(function()
    SimBags.setSize(w, 0, 4)
  end, "SimBags.setSize: bag 0 holds items beyond slot 4")
end

local function test_add_checks_its_arguments(w)
  A.errors(function()
    SimBags.add(w, "x", 1)
  end, "SimBags.add: itemID must be a number")
  A.errors(function()
    SimBags.add(w, LH.STACK, 0)
  end, "SimBags.add: count must be a positive whole number")
end

local function test_place_names_itself_in_its_errors(w)
  A.errors(function()
    SimBags.place(w, LH.STACK, 1.5)
  end, "SimBags.place: count must be a positive whole number")
end

local function test_clear_empties_and_tells_the_addon(w)
  SimBags.add(w, LH.STACK, 1)
  local ev = SH.record(w, { "BAG_UPDATE", "BAG_UPDATE_DELAYED" })
  SimBags.clear(w)
  A.same({ _G.C_Container.GetContainerItemInfo(0, 1), #ev, SimBags.freeSlots(w) }, { nil, 2, 16 })
end

local function test_use_container_item_is_only_recorded(w)
  SimBags.add(w, LH.STACK, 1)
  _G.C_Container.UseContainerItem(0, 1)
  A.eq(w.mock.requests[#w.mock.requests].api, "C_Container.UseContainerItem")
  A.eq(_G.C_Container.GetContainerItemID(0, 1), LH.STACK) -- nothing moves
end

local function test_reset_empties_the_bags_and_tells_the_addon(w)
  SimBags.add(w, LH.STACK, 1)
  local ev = SH.record(w, { "BAG_UPDATE", "BAG_UPDATE_DELAYED" })
  Sim.reset(w)
  A.same({ _G.C_Container.GetContainerItemInfo(0, 1), #ev }, { nil, 2 })
end

local function test_a_reload_keeps_the_bags_silently()
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    LH.items(sess.w)
    SimBags.setSize(sess.w, 1, 2)
    SimBags.add(sess.w, LH.STACK, 7)
    SH.reloaded(sess, function(fresh)
      LH.items(fresh.w)
      local ev = SH.record(fresh.w, { "BAG_UPDATE", "BAG_UPDATE_DELAYED" })
      A.eq(_G.C_Container.GetContainerItemInfo(0, 2).stackCount, 2)
      A.eq(_G.C_Container.GetContainerNumSlots(1), 2)
      A.eq(#ev, 0)
    end)
  end)
end

return function()
  for _, flavor in ipairs(LH.FLAVORS) do
    local tests = {
      test_empty_bags,
      test_add_stacks_and_reports,
      test_a_second_bag_adds_its_slots,
      test_full_bags_take_nothing,
      test_full_bags_report_no_free_slot,
      test_fill_order_spans_bags,
      test_overflow_goes_to_the_next_bag,
      test_set_size_refuses_to_drop_items,
      test_add_checks_its_arguments,
      test_place_names_itself_in_its_errors,
      test_clear_empties_and_tells_the_addon,
      test_use_container_item_is_only_recorded,
      test_reset_empties_the_bags_and_tells_the_addon,
    }
    for _, t in ipairs(tests) do
      LH.withBags(flavor, t)
    end
  end
  test_a_reload_keeps_the_bags_silently()
end
