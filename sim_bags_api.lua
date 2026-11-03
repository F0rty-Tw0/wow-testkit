-- SimBagsApi: the C_Container fakes over w.sim.bags (SimBags). An invalid bag (not 0 to 4, or not a number) counts as
-- unscripted and returns nothing, except GetContainerNumSlots, which returns 0.
local M = {}

local Items = require("game.items")
local Requests = require("game.requests")
local SimBags = require("sim_bags")
local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

-- The slot where bag 1 sits in the equipment list.
-- source: assumed (spec 8.1) ContainerIDToInventoryID(bag) is 19 + bag for the four bag slots (bag slot 1 is inventory
-- slot 20).
local BAG_SLOT_BASE = 19

local function isBag(bag)
  return type(bag) == "number" and bag >= 0 and bag <= 4 and bag == math.floor(bag)
end

-- A name's fake that counts an invalid bag as unscripted and returns nothing for it.
local function onBag(w, name, fn)
  define(w, "C_Container." .. name, function(bag, ...)
    if not isBag(bag) then
      WorldApi.markUnscripted(w, "C_Container." .. name)

      return
    end

    return fn(bag, ...)
  end)
end

local function heldAt(w, bag, slot)
  return w.sim.bags.slots[bag][slot]
end

-- source: confirmed (the manifest struct ContainerItemInfo, all five flavors) the twelve field names; the defaults (not
-- locked, not readable, no loot, not filtered, not bound) are assumed.
local function itemInfo(w, held)
  local record = w.mock.items[held.itemID] or {}
  local noValue = (record.sellPrice or 0) == 0

  return {
    iconFileID = record.icon,
    stackCount = held.count,
    isLocked = false,
    quality = record.quality,
    isReadable = false,
    hasLoot = false,
    hyperlink = Items.itemLink(held.itemID, record),
    isFiltered = false,
    hasNoValue = noValue,
    itemID = held.itemID,
    isBound = false,
    itemName = record.name,
  }
end

local function installSlots(w)
  -- source: assumed (spec 8.1) an invalid bag (not 0 to 4, or not a number) has 0 slots and counts as unscripted.
  define(w, "C_Container.GetContainerNumSlots", function(bag)
    if not isBag(bag) then
      WorldApi.markUnscripted(w, "C_Container.GetContainerNumSlots")

      return 0
    end

    return w.sim.bags.sizes[bag]
  end)
  -- source: assumed (spec 8.1) bagFamily is 0, a general bag.
  onBag(w, "GetContainerNumFreeSlots", function(bag)
    return #SimBags.freeList(w, bag), 0
  end)
  onBag(w, "GetContainerFreeSlots", function(bag)
    return SimBags.freeList(w, bag)
  end)
  define(w, "C_Container.CalculateTotalNumberOfFreeBagSlots", function()
    return SimBags.freeSlots(w)
  end)
end

local function installItems(w)
  -- The nil answer of an empty slot; fn(held) reads a held stack.
  local function onSlot(name, fn)
    onBag(w, name, function(bag, slot)
      local held = heldAt(w, bag, slot)

      return held and fn(held) or nil
    end)
  end
  onSlot("GetContainerItemInfo", function(held)
    return itemInfo(w, held)
  end)
  onSlot("GetContainerItemLink", function(held)
    return itemInfo(w, held).hyperlink
  end)
  onSlot("GetContainerItemID", function(held)
    return held.itemID
  end)
  onBag(w, "HasContainerItem", function(bag, slot)
    return heldAt(w, bag, slot) ~= nil
  end)
end

-- source: assumed (spec 8.1) the backpack is "Backpack", a bag with slots is "Kit Bag N", an empty bag slot has no name.
local function bagName(w, bag)
  if bag == 0 then
    return "Backpack"
  end
  if w.sim.bags.sizes[bag] > 0 then
    return "Kit Bag " .. bag
  end
end

local function installBagNames(w)
  onBag(w, "GetBagName", function(bag)
    return bagName(w, bag)
  end)
  onBag(w, "ContainerIDToInventoryID", function(bag)
    if bag >= 1 then
      return BAG_SLOT_BASE + bag
    end
  end)
end

-- source: assumed (row B13) the client only asks: a pickup or a use is recorded and nothing moves.
local function installRequests(w)
  for _, name in ipairs({ "PickupContainerItem", "UseContainerItem" }) do
    local api = "C_Container." .. name
    define(w, api, function(...)
      Requests.record(w, api, ...)
    end)
  end
end

function M.install(w)
  installSlots(w)
  installItems(w)
  installBagNames(w)
  installRequests(w)
end

return M
