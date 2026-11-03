-- Sim slice 1 end to end: a held W walks the player toward a hostile dummy, the spell range, the moving events, the
-- position, the map and the party range all follow the one place. Slice 3 adds a melee kill: spawn, move, strike, kill,
-- PARTY_KILL before UNIT_DIED, and the combat ending 5 s later. Slice 4 adds the loot: open the corpse, take every slot, the
-- events in order, the money and the items in the bags.
local A = require("assert")
local Actors = require("combat_actors")
local Group = require("combat_group")
local H = require("tests.helpers.sim")
local LH = require("tests.helpers.sim_loot")
local SH = require("tests.helpers.sim_combat")
local Sim = require("sim")

local SPELL = 900101

local function watchMoves()
  local log = {}
  local frame = _G.CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_STARTED_MOVING")
  frame:RegisterEvent("PLAYER_STOPPED_MOVING")
  frame:SetScript("OnEvent", function(_, event, ...)
    log[#log + 1] = { event, ... }
  end)

  return log
end

local function inRange()
  if _G.C_Spell and _G.C_Spell.IsSpellInRange then
    return _G.C_Spell.IsSpellInRange(SPELL, "target")
  end

  return _G.IsSpellInRange(SPELL, "target") == 1
end

local function setup(w)
  w:setMock({ spells = { [SPELL] = { name = "Kit Reach", minRange = 0, maxRange = 10 } } })
  local dummy = Actors.add(w, { kind = "npc", name = "Dummy", hostile = true, pos = { x = 0, y = 10 } })
  Actors.setTarget(w, Actors.get(w, "player"), dummy)
end

local function test_holding_w_walks_into_spell_range()
  H.each({}, function(w, s)
    setup(w)
    local log = watchMoves()
    A.eq(inRange(), false)
    s:key("W", "down")
    s:simStep(0.5)
    A.eq(inRange(), false)
    s:simStep(0.6)
    A.eq(inRange(), true)
    s:key("W", "up")
    s:simStep(0.1)
    A.same(H.names(log), { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" })
    H.near(select(1, _G.UnitPosition("player")), -2.3)
    A.eq(select(2, _G.UnitPosition("player")), 0)
    A.eq(select(4, _G.UnitPosition("player")), Sim.MAP_ID)
  end)
end

local function test_the_map_follows_the_walk()
  H.each({}, function(_, s)
    if not (_G.C_Map and _G.C_Map.GetPlayerMapPosition) then
      return
    end
    s:key("W", "down")
    s:simStep(1.1)
    s:key("W", "up")
    s:simStep(0.1)
    local x, y = _G.C_Map.GetPlayerMapPosition(Sim.MAP_ID, "player"):GetXY()
    H.near(x, 0.5)
    H.near(y, 0.523)
  end)
end

local function test_party_range_follows_the_member()
  H.each({}, function(w)
    local ann = Actors.add(w, { kind = "player", name = "Ann", pos = { x = 0, y = 45 } })
    Group.set(w, { Actors.get(w, "player"), ann }, { raid = false })
    A.same({ _G.UnitInRange("party1") }, { false, true })
    Actors.setPos(w, ann, 0, 20)
    A.same({ _G.UnitInRange("party1") }, { true, true })
  end)
end

local function indexOfDeath(entries, mob)
  local found
  for i, entry in ipairs(entries) do
    if entry[2] == "UNIT_DIED" and entry[8] == mob.guid then
      found = i
    end
  end

  return found
end

local function countEvents(seen)
  local counts = {}
  for _, entry in ipairs(seen) do
    counts[entry.event] = (counts[entry.event] or 0) + 1
  end

  return counts
end

local function firstOf(seen, event)
  for _, entry in ipairs(seen) do
    if entry.event == event then
      return entry
    end
  end
end

local function test_melee_kill_sequence(w, s, flavor)
  local entries, player = w.combat.log.entries, w.sim.player
  local seen = SH.record(w, {
    "PLAYER_STARTED_MOVING",
    "PLAYER_STOPPED_MOVING",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "UI_ERROR_MESSAGE",
  })
  local mob = s:spawn({ health = 20 })
  s:clickUnit(mob, "RightButton")
  A.eq(_G.UnitGUID("target"), mob.guid, flavor)
  SH.walkIntoMelee(s, mob)
  SH.fightUntilDead(s, mob)
  A.eq(mob.isDead, true, flavor)
  local died = indexOfDeath(entries, mob)
  A.same({ entries[died - 2][2], entries[died - 1][2] }, { "SWING_DAMAGE", "PARTY_KILL" }, flavor)
  A.same({ entries[died - 2][4], entries[died - 1][4], entries[died - 1][8] }, { player.guid, player.guid, mob.guid }, flavor)
  s:simStep(5.1)
  local counts = countEvents(seen)
  local last = seen[#seen]
  A.same({
    counts.PLAYER_STARTED_MOVING,
    counts.PLAYER_STOPPED_MOVING,
    counts.PLAYER_REGEN_DISABLED,
    counts.PLAYER_REGEN_ENABLED,
    counts.UI_ERROR_MESSAGE,
  }, { 1, 1, 1, 1, 1 }, flavor)
  A.eq(firstOf(seen, "UI_ERROR_MESSAGE")[4], _G.ERR_BADATTACKPOS, flavor) -- the walk in is out of range, not out of facing
  A.same({ last.event, math.abs((last.ts - entries[died][1]) - 5) < 0.02 }, { "PLAYER_REGEN_ENABLED", true }, flavor)
end

local LOOT_EVENTS = {
  "LOOT_READY",
  "LOOT_OPENED",
  "ITEM_PUSH",
  "BAG_UPDATE",
  "BAG_UPDATE_DELAYED",
  "CHAT_MSG_LOOT",
  "LOOT_SLOT_CLEARED",
  "LOOT_CLOSED",
  "CHAT_MSG_MONEY",
  "PLAYER_MONEY",
  "UI_ERROR_MESSAGE",
}

local function test_loot_sequence(w, s, flavor)
  local ev = SH.record(w, LOOT_EVENTS)
  local mob = s:spawn({ health = 1 }) -- default loot, 20 yd ahead, idle
  s:place(mob.pos.x, mob.pos.y - 1) -- next to it, still facing north
  s:clickUnit(mob, "RightButton") -- target + attack
  local guard = 0
  while not mob.isDead and guard < 900 do
    s:simStep(0.25)
    guard = guard + 1
  end
  A.same({ mob.isDead, mob.lootable }, { true, true }, flavor)
  s:clickUnit(mob, "RightButton") -- loot window opens
  A.eq(LH.subsequence(LH.names(ev), { "LOOT_READY", "LOOT_OPENED" }), true, flavor)
  _G.LootSlot(1)
  _G.LootSlot(2)
  _G.LootSlot(3) -- cleared slots keep their numbers while the window is open
  -- source: assumed (user ruling, sim fix wave 4) each item slot fires ITEM_PUSH, BAG_UPDATE, BAG_UPDATE_DELAYED,
  -- CHAT_MSG_LOOT, LOOT_SLOT_CLEARED, exactly and in that order.
  A.same(LH.from(LH.names(ev), "LOOT_READY"), {
    "LOOT_READY",
    "LOOT_OPENED",
    "PLAYER_MONEY",
    "CHAT_MSG_MONEY",
    "LOOT_SLOT_CLEARED",
    "ITEM_PUSH",
    "BAG_UPDATE",
    "BAG_UPDATE_DELAYED",
    "CHAT_MSG_LOOT",
    "LOOT_SLOT_CLEARED",
    "ITEM_PUSH",
    "BAG_UPDATE",
    "BAG_UPDATE_DELAYED",
    "CHAT_MSG_LOOT",
    "LOOT_SLOT_CLEARED",
    "LOOT_CLOSED",
  }, flavor)
  A.same({ _G.GetMoney(), mob.lootable, w.sim.loot.window }, { 37, false, nil }, flavor)
  local first, second = _G.C_Container.GetContainerItemInfo(0, 1), _G.C_Container.GetContainerItemInfo(0, 2)
  A.same({ first.itemID, first.stackCount, second.itemID, second.stackCount }, { 900201, 1, 900202, 2 }, flavor)
  A.eq(#w.warnings, 0, flavor)
end

return function()
  test_holding_w_walks_into_spell_range()
  test_the_map_follows_the_walk()
  test_party_range_follows_the_member()
  H.each({}, function(w, s, flavor)
    test_melee_kill_sequence(w, s, flavor)
  end)
  H.each({}, function(w, s, flavor)
    test_loot_sequence(w, s, flavor)
  end)
end
