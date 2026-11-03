-- Sim loot test helper: kit items, bags and event-order checks that the loot tasks of phase 4 share. Tests never read a
-- client extract or install.
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SimBags = require("sim_bags")
local SimMobs = require("sim_mobs")

local M = {}

M.FLAVORS = SH.FLAVORS

-- Every event a loot window can fire, for tests that record the whole flow.
M.LOOT_EVENTS = {
  "LOOT_READY",
  "LOOT_OPENED",
  "LOOT_SLOT_CLEARED",
  "LOOT_CLOSED",
  "ITEM_PUSH",
  "BAG_UPDATE",
  "BAG_UPDATE_DELAYED",
  "CHAT_MSG_LOOT",
  "CHAT_MSG_MONEY",
  "PLAYER_MONEY",
}

-- Kit items for bag tests (no extract): a stack of 5 and a single.
M.STACK, M.SINGLE = 900301, 900302

local ITEMS = {
  [M.STACK] = { name = "Kit Stack", quality = 1, stackCount = 5, icon = 900301 },
  [M.SINGLE] = { name = "Kit Single", quality = 2, stackCount = 1, icon = 900302 },
}

function M.items(w)
  for id, record in pairs(ITEMS) do
    w.mock.items[id] = record
  end
end

-- Runs fn(w, s, player) on a sim world with the kit bag items stored.
function M.withBags(flavor, fn)
  SH.withSim(flavor, function(w, s, player)
    M.items(w)
    fn(w, s, player)
  end)
end

-- Fills every free slot with a full stack of itemID; returns the slot count filled.
function M.fillBags(w, itemID)
  local stack = w.mock.items[itemID].stackCount or 1
  local filled = 0
  while SimBags.place(w, itemID, stack) > 0 do
    filled = filled + 1
  end

  return filled
end

-- A dead hostile mob at (x, y) with the given loot table (nil = default); returns the actor.
function M.corpse(w, x, y, loot)
  local mob = SimMobs.spawn(w, { pos = { x = x, y = y }, health = 1, loot = loot })
  Resolve.kill(w, mob)

  return mob
end

-- Event names of a SH.record list, in order.
function M.names(ev)
  local out = {}
  for _, entry in ipairs(ev) do
    out[#out + 1] = entry.event
  end

  return out
end

-- "money:37", "item:900201x1" per drop of actor, in order.
function M.dropList(actor)
  local out = {}
  for _, drop in ipairs(actor.drops) do
    out[#out + 1] = drop.kind == "money" and "money:" .. drop.copper or string.format("item:%dx%d", drop.itemID, drop.count)
  end

  return out
end

-- The names from the first `first` on (empty when names lacks it).
function M.from(names, first)
  local out = {}
  for _, name in ipairs(names) do
    if #out > 0 or name == first then
      out[#out + 1] = name
    end
  end

  return out
end

-- True when `wanted` (list of event names) appears in `names` in order, gaps allowed.
function M.subsequence(names, wanted)
  local next = 1
  for _, name in ipairs(names) do
    if name == wanted[next] then
      next = next + 1
    end
  end

  return next > #wanted
end

-- A frame wired like Blizzard's LootFrame (retail lootframe.lua:30,139-147; classic :13-19): OnHide calls CloseLoot and
-- the events fill frame.rows[i] with the slot name. style "retail" registers LOOT_OPENED at creation and the other three
-- in OnShow (unregistered in OnHide); "classic" registers all four plus LOOT_READY at creation.
local ROW_EVENTS = { "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED" }

local function fillRows(frame)
  frame.rows = {}
  for i = 1, _G.GetNumLootItems() do
    if _G.LootSlotHasItem(i) then
      frame.rows[i] = select(2, _G.GetLootSlotInfo(i))
    end
  end
  frame:Show()
end

local function onEvent(frame, event, slot)
  if event == "LOOT_OPENED" then
    fillRows(frame)
  elseif event == "LOOT_SLOT_CLEARED" then
    frame.rows[slot] = nil
  elseif event == "LOOT_SLOT_CHANGED" then
    frame.rows[slot] = select(2, _G.GetLootSlotInfo(slot))
  elseif event == "LOOT_CLOSED" then
    frame:Hide()
  end
end

function M.miniLootFrame(_w, style)
  local frame = _G.CreateFrame("Frame")
  frame.rows = {}
  frame:Hide() -- Blizzard's frame starts hidden, so the first Show runs OnShow
  frame:SetScript("OnEvent", onEvent)
  frame:SetScript("OnHide", function(self)
    _G.CloseLoot()
    if style == "retail" then
      for _, event in ipairs(ROW_EVENTS) do
        self:UnregisterEvent(event)
      end
    end
  end)
  frame:RegisterEvent("LOOT_OPENED")
  if style == "classic" then
    for _, event in ipairs(ROW_EVENTS) do
      frame:RegisterEvent(event)
    end
    frame:RegisterEvent("LOOT_READY")
  else
    frame:SetScript("OnShow", function(self)
      for _, event in ipairs(ROW_EVENTS) do
        self:RegisterEvent(event)
      end
    end)
  end

  return frame
end

return M
