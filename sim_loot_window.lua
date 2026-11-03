-- SimLootWindow: the sim player's loot window. open shows one corpse's drops (LOOT_READY, LOOT_OPENED); slot takes a drop
-- into the player's money or bags; close ends the window (LOOT_CLOSED). The window is w.sim.loot.window = { guid, auto },
-- the corpse's drops are actor.drops (SimLoot rolls them): { kind = "money", copper } or { kind = "item", itemID, count },
-- with taken = true once looted. Events go through say, so only what the flavor's manifest lists is fired.
local M = {}

local AddonEnv = require("addon_env")
local Actors = require("combat_actors")
local Combat = require("combat")
local Items = require("game.items")
local SimBags = require("sim_bags")
local SimRange = require("sim_range")
local SimTarget = require("sim_target")

local unpack = unpack

local COIN_PARTS = { { 10000, "GOLD_AMOUNT" }, { 100, "SILVER_AMOUNT" }, { 1, "COPPER_AMOUNT" } }

-- Fires event with args cut to the manifest's payload length; an event the manifest lacks is skipped.
-- source: assumed (spec 8.1) the manifest decides which loot events a flavor has, and an event without payload fires bare.
function M.say(w, event, ...)
  local spec = w.manifest.events[event]
  if not spec then
    return
  end
  local count = spec.payload and #spec.payload or 0
  local args = { ... }
  Combat.fire(w, event, unpack(args, 1, count))
end

-- "1 Gold, 23 Silver, 45 Copper" from the three amount strings: parts joined with sep, a zero part skipped.
-- source: assumed (spec 8.1) the client builds the coin text from GOLD_AMOUNT, SILVER_AMOUNT and COPPER_AMOUNT; the
-- LootFrame row joins them with a newline, the chat line with ", ".
function M.coinText(copper, sep)
  local parts, left = {}, copper
  for _, part in ipairs(COIN_PARTS) do
    local unit, name = part[1], part[2]
    local amount = math.floor(left / unit)
    left = left - amount * unit
    if amount > 0 then
      parts[#parts + 1] = string.format(_G[name], amount)
    end
  end

  return table.concat(parts, sep)
end

local function hasUntaken(actor)
  for _, drop in ipairs(actor.drops or {}) do
    if not drop.taken then
      return true
    end
  end

  return false
end

local function inRange(w, actor)
  return SimRange.distance(w.sim.player, actor) <= SimTarget.INTERACT_RANGE
end

-- hasLoot (a drop not taken), canLoot (hasLoot, the actor dead and within INTERACT_RANGE).
-- source: assumed meaning of the two returns of CanLootUnit (listed with those names in api/<flavor>/PlayerScript.lua).
function M.canLoot(w, actor)
  local hasLoot = hasUntaken(actor)
  local canLoot = hasLoot and actor.isDead == true and inRange(w, actor)

  return hasLoot, canLoot
end

-- The corpse the window shows, or nil.
function M.corpse(w)
  local window = w.sim.loot.window

  return window and Actors.get(w, window.guid)
end

-- source: assumed (spec 8.1) the window opens by itself when autoLootDefault and the AUTOLOOTTOGGLE key disagree.
local function autoLoot(w)
  local cvarOn = AddonEnv.global(w, "GetCVarBool")("autoLootDefault")
  local toggled = AddonEnv.global(w, "IsModifiedClick")("AUTOLOOTTOGGLE")

  return cvarOn ~= toggled
end

-- Takes every slot, in order (the loop ends early when the window closes: slot ignores a closed window).
local function takeAll(w, count)
  for i = 1, count do
    M.slot(w, i)
  end
end

-- Opens the corpse's window. Returns whether it is open on actor: false for no loot, a living actor or too far (the
-- too-far error fires); an open window on the same corpse is left alone; on another corpse it closes first.
-- source: assumed order (no Blizzard source states LOOT_READY before LOOT_OPENED; LootFrame reads neither order-dependent).
function M.open(w, actor)
  local state = w.sim.loot
  local lootableCorpse = hasUntaken(actor) and actor.isDead
  if not lootableCorpse then
    return false
  end
  if state.window and state.window.guid == actor.guid then
    return true
  end
  if not inRange(w, actor) then
    SimTarget.uiError(w, "ERR_LOOT_TOO_FAR")

    return false
  end
  M.close(w)
  local auto = autoLoot(w)
  state.window = { guid = actor.guid, auto = auto }
  M.say(w, "LOOT_READY", auto)
  M.say(w, "LOOT_OPENED", auto, false)
  if auto then
    takeAll(w, #actor.drops)
  end

  return true
end

-- A chat event for the player: text, the player's name and guid, the next line id; the tuple is cut by say.
-- source: assumed (spec 8.1) the 18 values of CHAT_MSG_*: text, sender name, five empty strings and zeros, the line id,
-- the sender guid, and four false flags (retail has the 18th, nil).
local function chat(w, event, text)
  local state, player = w.sim.loot, w.sim.player
  state.line = state.line + 1
  M.say(w, event, text, player.name, "", "", "", "", 0, 0, "", 0, state.line, player.guid, 0, false, false, false, false, nil)
end

-- source: assumed (spec 8.1) the money order PLAYER_MONEY, CHAT_MSG_MONEY, then LOOT_SLOT_CLEARED; no Blizzard source
-- orders them.
local function takeMoney(w, i, drop)
  w.mock.money = w.mock.money + drop.copper
  drop.taken = true
  M.say(w, "PLAYER_MONEY")
  chat(w, "CHAT_MSG_MONEY", string.format(_G.YOU_LOOT_MONEY, M.coinText(drop.copper, ", ")))
  M.say(w, "LOOT_SLOT_CLEARED", i)
end

-- source: assumed the chat line names the count (LOOT_ITEM_SELF_MULTIPLE) only when more than one was placed, as the two
-- global strings' wording implies.
local function lootLine(w, drop, placed)
  local link = Items.itemLink(drop.itemID, w.mock.items[drop.itemID] or {})
  if placed > 1 then
    return string.format(_G.LOOT_ITEM_SELF_MULTIPLE, link, placed)
  end

  return string.format(_G.LOOT_ITEM_SELF, link)
end

-- Puts the item in the bags: nothing fits is an error and the slot stays; some fits and the rest stays in the slot.
-- source: assumed order ITEM_PUSH, BAG_UPDATE, BAG_UPDATE_DELAYED, CHAT_MSG_LOOT, then the slot event (user ruling, sim
-- fix wave 4; no Blizzard source orders them).
-- source: assumed (spec 8.1) a partial fit fires LOOT_SLOT_CHANGED, then the ERR_INV_FULL error, and the slot keeps the
-- rest; nothing fits fires the error alone.
local function takeItem(w, i, drop)
  local placed, rest, touched = SimBags.place(w, drop.itemID, drop.count)
  if placed == 0 then
    SimTarget.uiError(w, "ERR_INV_FULL")

    return
  end
  -- The drop changes before any event: a handler that calls CloseLoot must see it taken (or cut to rest), so the close
  -- drops it instead of keeping a slot that LootSlotHasItem denies.
  local line = lootLine(w, drop, placed)
  local record = w.mock.items[drop.itemID] or {}
  if rest > 0 then
    drop.count = rest
  else
    drop.taken = true
  end
  M.say(w, "ITEM_PUSH", touched[1], record.icon)
  SimBags.notify(w, touched)
  chat(w, "CHAT_MSG_LOOT", line)
  if rest > 0 then
    M.say(w, "LOOT_SLOT_CHANGED", i)
    SimTarget.uiError(w, "ERR_INV_FULL")

    return
  end
  M.say(w, "LOOT_SLOT_CLEARED", i)
end

-- Takes slot i. A closed window, an unknown slot and a taken slot are ignored. The last slot taken closes the window.
-- source: assumed (spec 8.1) the client closes an emptied loot window by itself (LOOT_CLOSED after the last
-- LOOT_SLOT_CLEARED).
function M.slot(w, i)
  local actor = M.corpse(w)
  local drop = actor and actor.drops[i]
  if not drop or drop.taken then
    return
  end
  if drop.kind == "money" then
    takeMoney(w, i, drop)
  else
    takeItem(w, i, drop)
  end
  if not hasUntaken(actor) then
    M.close(w)
  end
end

-- Ends the window: window = nil first, the taken drops go (the corpse keeps the rest, renumbered on reopen), LOOT_CLOSED
-- fires once.
-- source: confirmed (Blizzard LootFrame OnHide calls CloseLoot(), retail lootframe.lua:142-147, classic :326, and the frame
-- hides on LOOT_CLOSED: the call re-enters, so a second close must do nothing).
function M.close(w)
  local state = w.sim.loot
  local window = state.window
  if not window then
    return
  end
  state.window = nil
  local actor = Actors.get(w, window.guid)
  if actor then
    local kept = {}
    for _, drop in ipairs(actor.drops) do
      if not drop.taken then
        kept[#kept + 1] = drop
      end
    end
    actor.drops, actor.lootable = kept, #kept > 0
  end
  M.say(w, "LOOT_CLOSED")
end

-- The frame hook: the window closes when the player is farther than INTERACT_RANGE from the corpse.
-- source: assumed (spec 8.1) the real range is server-side.
function M.walkAway(w)
  local actor = M.corpse(w)
  if actor and not inRange(w, actor) then
    M.close(w)
  end
end

-- The despawn listener: the window closes when its corpse leaves.
local function closeOnDespawn(w, actor)
  local window = w.sim.loot.window
  if window and window.guid == actor.guid then
    M.close(w)
  end
end

-- Hooks the walk-away check and the close on reset on the sim, and closes the window when its corpse leaves.
function M.install(w)
  local hooks = w.sim.hooks
  hooks.frame = hooks.frame or {}
  hooks.reset = hooks.reset or {}
  table.insert(hooks.frame, M.walkAway)
  table.insert(hooks.reset, M.close)
  Combat.listen(w, "despawn", function(actor)
    closeOnDespawn(w, actor)
  end)
end

return M
