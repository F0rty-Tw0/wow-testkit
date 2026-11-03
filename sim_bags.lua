-- SimBags: the sim player's five bags (0 is the backpack, 1 to 4 the bag slots). place puts items in the client's order
-- without a sound; add also tells the addon (BAG_UPDATE per changed bag, ascending, then one BAG_UPDATE_DELAYED).
-- w.sim.bags = { sizes = { [bag] = size }, slots = { [bag] = { [slot] = { itemID, count } } } }; the C_Container fakes read it.
local M = {}

local Combat = require("combat")
local SimState = require("sim_state")

M.BAGS = { 0, 1, 2, 3, 4 }

-- source: assumed (spec 8.1) the player starts with a 16 slot backpack and no other bag.
local BACKPACK_SIZE = 16

-- source: assumed (spec 8.1) the item store holds the stack size (BlizzardData.items fills it from ItemSparse); an item with
-- none stacks to 1.
local function stackOf(w, itemID)
  local record = w.mock.items[itemID]

  return record and record.stackCount or 1
end

local function newBags()
  local sizes, slots = {}, {}
  for _, bag in ipairs(M.BAGS) do
    sizes[bag] = bag == 0 and BACKPACK_SIZE or 0
    slots[bag] = {}
  end

  return { sizes = sizes, slots = slots }
end

-- Tops up the stacks of itemID with room (bags 0 to 4, slots ascending); returns what is left of count.
-- source: assumed (spec 8.1) the client's default stacking order: partial stacks first, then empty slots, bags 0 to 4 and
-- slots ascending. No source states it.
local function fillPartial(w, itemID, count, touched)
  local bags, room = w.sim.bags, stackOf(w, itemID)
  local left = count
  for _, bag in ipairs(M.BAGS) do
    for slot = 1, bags.sizes[bag] do
      local held = bags.slots[bag][slot]
      local fits = held and held.itemID == itemID and held.count < room and left > 0
      if fits then
        local moved = math.min(room - held.count, left)
        held.count, left, touched[bag] = held.count + moved, left - moved, true
      end
    end
  end

  return left
end

-- Puts what is left of count into the empty slots in the same order; returns what is left after that.
local function fillEmpty(w, itemID, count, touched)
  local bags, room = w.sim.bags, stackOf(w, itemID)
  local left = count
  for _, bag in ipairs(M.BAGS) do
    for slot = 1, bags.sizes[bag] do
      if left > 0 and not bags.slots[bag][slot] then
        local moved = math.min(room, left)
        bags.slots[bag][slot], left, touched[bag] = { itemID = itemID, count = moved }, left - moved, true
      end
    end
  end

  return left
end

local function sortedBags(set)
  local list = {}
  for _, bag in ipairs(M.BAGS) do
    if set[bag] then
      list[#list + 1] = bag
    end
  end

  return list
end

-- Raises, naming api and blaming the caller of the public entry that called check.
local function check(api, itemID, count)
  if type(itemID) ~= "number" then
    error(api .. ": itemID must be a number", 3)
  end
  local whole = type(count) == "number" and count >= 1 and count == math.floor(count)
  if not whole then
    error(api .. ": count must be a positive whole number", 3)
  end
end

local function placeChecked(w, itemID, count)
  local touched = {}
  local afterPartial = fillPartial(w, itemID, count, touched)
  local rest = fillEmpty(w, itemID, afterPartial, touched)

  return count - rest, rest, sortedBags(touched)
end

-- Puts count of itemID in the bags without events. Returns placed, rest, touched (the changed bag ids, ascending).
function M.place(w, itemID, count)
  check("SimBags.place", itemID, count)

  return placeChecked(w, itemID, count)
end

-- One BAG_UPDATE(bag) per touched bag in the list's order, then one BAG_UPDATE_DELAYED.
-- source: assumed (spec 8.1) the client batches a change into BAG_UPDATE per bag and a closing BAG_UPDATE_DELAYED.
function M.notify(w, touched)
  for _, bag in ipairs(touched) do
    Combat.fire(w, "BAG_UPDATE", bag)
  end
  Combat.fire(w, "BAG_UPDATE_DELAYED")
end

-- place, then notify when a bag changed. Returns placed, rest, touched.
function M.add(w, itemID, count)
  check("SimBags.add", itemID, count)
  local placed, rest, touched = placeChecked(w, itemID, count)
  if #touched > 0 then
    M.notify(w, touched)
  end

  return placed, rest, touched
end

-- Gives bag a size. Raises when an item sits past the new size.
function M.setSize(w, bag, size)
  local bags = w.sim.bags
  for slot in pairs(bags.slots[bag]) do
    if slot > size then
      error(string.format("SimBags.setSize: bag %d holds items beyond slot %d", bag, size), 2)
    end
  end
  bags.sizes[bag] = size
end

-- Empties every bag and tells the addon about each bag that held something (the reset hook: the addon must see them empty).
function M.clear(w)
  local bags, touched = w.sim.bags, {}
  for _, bag in ipairs(M.BAGS) do
    touched[bag] = next(bags.slots[bag]) ~= nil
    bags.slots[bag] = {}
  end
  local changed = sortedBags(touched)
  if #changed > 0 then
    M.notify(w, changed)
  end
end

-- The free slot numbers of bag, ascending.
function M.freeList(w, bag)
  local list = {}
  for slot = 1, w.sim.bags.sizes[bag] do
    if not w.sim.bags.slots[bag][slot] then
      list[#list + 1] = slot
    end
  end

  return list
end

function M.freeSlots(w)
  local free = 0
  for _, bag in ipairs(M.BAGS) do
    free = free + #M.freeList(w, bag)
  end

  return free
end

-- The persisted shape: sizes as a list in M.BAGS order and the items as { bag, slot, itemID, count } sorted by bag, slot.
local function export(w)
  local bags, sizes, items = w.sim.bags, {}, {}
  for index, bag in ipairs(M.BAGS) do
    sizes[index] = bags.sizes[bag]
    for slot = 1, bags.sizes[bag] do
      local held = bags.slots[bag][slot]
      if held then
        items[#items + 1] = { bag, slot, held.itemID, held.count }
      end
    end
  end

  return { sizes = sizes, items = items }
end

-- Silent: the addon reads the bags after the reload as it does after a login.
local function restore(w, data)
  local bags = newBags()
  for index, bag in ipairs(M.BAGS) do
    bags.sizes[bag] = data.sizes[index]
  end
  for _, row in ipairs(data.items) do
    bags.slots[row[1]][row[2]] = { itemID = row[3], count = row[4] }
  end
  w.sim.bags = bags
end

-- Puts the bags, the reset hook and the reload state on the sim world (sim_units installs the C_Container fakes next).
function M.install(w)
  w.sim.bags = newBags()
  w.sim.hooks.reset = w.sim.hooks.reset or {}
  table.insert(w.sim.hooks.reset, M.clear)
  SimState.persist(w, "bags", { export = export, restore = restore })
end

return M
