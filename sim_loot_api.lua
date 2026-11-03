-- SimLootApi: the Blizzard-named loot reads and calls over the open window (SimLootWindow). A slot number is the drop's
-- place in actor.drops, taken ones included; a closed window, an unknown slot and a taken slot answer nothing.
-- source: assumed (spec 8.1) slots keep their numbers while the window is open and GetNumLootItems counts taken ones:
-- Blizzard's LootFrame clears a row on LOOT_SLOT_CLEARED by its slot number (retail lootframe.lua:111, classic :43).
local M = {}

local Actors = require("combat_actors")
local Items = require("game.items")
local Requests = require("game.requests")
local SimLoot = require("sim_loot")
local SimLootWindow = require("sim_loot_window")
local State = require("game.state")
local define = State.define

-- source: confirmed (Enum.LootSlotType in api/<flavor>/LootConstants.lua) None 0, Item 1, Money 2.
local SLOT_NONE, SLOT_ITEM, SLOT_MONEY = 0, 1, 2

-- source: assumed the coin row shows the coin icon.
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- source: assumed (classic lootframe.lua:168) the slot holds an item or money until it is taken.
local function dropAt(w, i)
  local actor = SimLootWindow.corpse(w)
  local drop = actor and actor.drops[i]

  return drop and not drop.taken and drop or nil
end

local function recordOf(w, drop)
  return w.mock.items[drop.itemID] or {}
end

-- The ten values of GetLootSlotInfo for a drop.
-- source: confirmed (order) both extracts destructure texture, item, quantity, currencyID, quality, locked at retail
-- lootframe.lua:157 and tbc :183; the rest (isQuestItem, questID, isActive, isCoin) and every value below are assumed.
local function slotInfo(w, drop)
  if drop.kind == "money" then
    return COIN_ICON, SimLootWindow.coinText(drop.copper, "\n"), 0, nil, 0, false, false, nil, false, true
  end
  local record = recordOf(w, drop)

  return record.icon, record.name, drop.count, nil, record.quality, false, false, nil, false, false
end

local function installSlots(w)
  define(w, "GetNumLootItems", function()
    local actor = SimLootWindow.corpse(w)

    return actor and #actor.drops or 0
  end)
  define(w, "LootSlotHasItem", function(i)
    return dropAt(w, i) ~= nil
  end)
  define(w, "GetLootSlotInfo", function(i)
    local drop = dropAt(w, i)
    if drop then
      return slotInfo(w, drop)
    end
  end)
  define(w, "GetLootSlotType", function(i)
    local drop = dropAt(w, i)
    if not drop then
      return SLOT_NONE
    end

    return drop.kind == "money" and SLOT_MONEY or SLOT_ITEM
  end)
  define(w, "GetLootSlotLink", function(i)
    local drop = dropAt(w, i)
    if drop and drop.kind == "item" then
      return Items.itemLink(drop.itemID, recordOf(w, drop))
    end
  end)
end

-- source: assumed shape of GetLootInfo: one row per slot not taken, { item, texture, quantity, quality, locked,
-- isQuestItem, questId, isActive }.
local function lootInfo(w)
  local actor, rows = SimLootWindow.corpse(w), {}
  for i in ipairs(actor and actor.drops or {}) do
    local drop = dropAt(w, i)
    if drop then
      local texture, name, quantity, _, quality, locked, quest, questId, active = slotInfo(w, drop)
      rows[#rows + 1] = {
        item = name,
        texture = texture,
        quantity = quantity,
        quality = quality,
        locked = locked,
        isQuestItem = quest,
        questId = questId,
        isActive = active,
      }
    end
  end

  return rows
end

-- source: assumed (GetLootSourceInfo) the corpse's guid and the slot's quantity.
local function sourceInfo(w, i)
  local drop = dropAt(w, i)
  if drop then
    return SimLootWindow.corpse(w).guid, (select(3, slotInfo(w, drop)))
  end
end

local function installCalls(w)
  define(w, "GetLootInfo", function()
    return lootInfo(w)
  end)
  define(w, "LootSlot", function(i)
    SimLoot.slot(w, i)
  end)
  define(w, "CloseLoot", function()
    SimLoot.close(w)
  end)
  -- source: assumed the client only asks: the confirmation is recorded and nothing else happens.
  define(w, "ConfirmLootSlot", function(...)
    Requests.record(w, "ConfirmLootSlot", ...)
  end)
  define(w, "GetLootSourceInfo", function(i)
    return sourceInfo(w, i)
  end)
end

local function installFlags(w)
  -- source: assumed the sim has no fishing: every loot window is a corpse's.
  define(w, "IsFishingLoot", function()
    return false
  end)
  -- source: assumed the group loot threshold is 2 (uncommon).
  define(w, "GetLootThreshold", function()
    return 2
  end)
  -- source: assumed legacy loot mode (old raids looted solo) is off: the sim has no instance.
  define(w, "C_Loot.IsLegacyLootModeEnabled", function()
    return false
  end)
  -- source: assumed an unknown guid is false, false.
  define(w, "CanLootUnit", function(guid)
    local actor = Actors.get(w, guid)
    if not actor then
      return false, false
    end

    return SimLoot.canLoot(w, actor)
  end)
end

function M.install(w)
  installSlots(w)
  installCalls(w)
  installFlags(w)
end

return M
