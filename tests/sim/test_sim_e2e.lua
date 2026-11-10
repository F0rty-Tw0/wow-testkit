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
local SessionH = require("tests.helpers.session")
local SimMelee = require("sim_melee")
local SimMobs = require("sim_mobs")
local SimSpells = require("sim_spells")
local SimWorld = require("sim_world")
local SP = require("tests.helpers.sim_spells")

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

local SPELL_EVENTS = {
  "UNIT_SPELLCAST_START",
  "UNIT_SPELLCAST_SUCCEEDED",
  "PLAYER_STARTED_MOVING",
  "PLAYER_STOPPED_MOVING",
  "PLAYER_REGEN_DISABLED",
  "ACTIONBAR_UPDATE_COOLDOWN",
}

-- The position of the first entry in names that is `event` (nil when none).
local function indexOf(names, event)
  for i, name in ipairs(names) do
    if name == event then
      return i
    end
  end
end

-- Whether the events appear in names in this order (other events may sit between them).
local function inOrder(names, events)
  local at = 0
  for _, event in ipairs(events) do
    local rest = {}
    for i = at + 1, #names do
      rest[#rest + 1] = names[i]
    end
    local found = indexOf(rest, event)
    if not found then
      return false
    end
    at = at + found
  end

  return true
end

local function eventNames(log)
  local names = {}
  for i, entry in ipairs(log) do
    names[i] = entry.event
  end

  return names
end

-- A dummy that never swings back at (x, y), alive for the whole scenario, targeted by the player.
local function dummyAt(w, x, y)
  local mob = SimMobs.spawn(w, { pos = { x = x, y = y }, health = 100000, ai = false })
  Actors.setTarget(w, w.sim.player, mob)

  return mob
end

-- Slice 5: the Warrior charges a pack mob from 20 yd and fights it.
local function test_charge_lands_in_melee_stuns_and_starts_the_fight()
  H.withSim("retail", { class = "WARRIOR" }, function(w, s)
    local seen = SH.record(w, SPELL_EVENTS)
    local pack = s:spawnPack(3)
    local mob = pack[2]
    s:clickUnit(mob)
    _G.UseAction(1)
    s:simStep(1.2)
    local player = w.sim.player
    A.same({ SimMelee.inRange(player, mob), player.casting, player.power > 0 }, { true, nil, true })
    local charge = SP.effectsOfKind(w, "charge")[1]
    A.same({ charge.spellID, charge.from.y < charge.to.y, SP.effectsOfKind(w, "aura")[1].style }, { 100, true, "stun" })
    s:clickUnit(mob, "RightButton")
    s:simStep(5.5)
    -- source: assumed (Task 5.7 finding) the landing plays the stun and the energize in the run's last frame, which starts
    -- the combat, and the walk stops with the next frame hook: REGEN_DISABLED comes before STOPPED_MOVING.
    A.eq(
      inOrder(eventNames(seen), {
        "UNIT_SPELLCAST_SUCCEEDED",
        "PLAYER_STARTED_MOVING",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_STOPPED_MOVING",
      }),
      true,
      table.concat(eventNames(seen), ",")
    )
    A.eq(mob.health < mob.healthMax, true)
    A.eq(#w.warnings, 0)
  end)
end

-- Slice 5: the same world turned Mage casts Fireball with a bar and Blizzard on the ground.
local function test_the_mage_casts_fireball_and_drops_a_blizzard()
  H.withSim("retail", { class = "WARRIOR" }, function(w, s)
    Sim.reset(w, "MAGE")
    local player = w.sim.player
    local mob = dummyAt(w, 0, 10)
    local full = mob.health
    _G.UseAction(1)
    s:simStep(0.1)
    A.same({ player.casting.spellID, SimWorld.build(w).player.casting.spellID }, { 133, 133 })
    s:simStep(3)
    A.same({ player.casting, mob.health < full, player.power < player.powerMax }, { nil, true, true })
    local health = mob.health
    s:simStep(1)
    _G.UseAction(3)
    A.same({ _G.SpellIsTargeting(), SimWorld.build(w).targeting.radius }, { true, 8 })
    s:clickGround(0, 10)
    s:simStep(5)
    local ground = SP.effectsOfKind(w, "ground")
    A.same({ #ground, ground[1].radius }, { 1, 8 })
    A.eq(SP.hitsOn(w, "SPELL_PERIODIC_DAMAGE", mob.guid) >= 1, true)
    A.eq(mob.health < health, true)
  end)
end

-- Slice 5, classic: a dodged swing lights the Overpower glow.
local function test_a_dodge_lights_the_overpower_glow_on_tbc()
  H.withSim("tbc", { class = "WARRIOR" }, function(w, s)
    local seen = SH.record(w, { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" })
    dummyAt(w, 0, -9)
    SimMelee.start(w)
    local guard = 0
    while #seen == 0 and guard < 80 do
      s:simStep(0.5)
      guard = guard + 1
    end
    SimMelee.stop(w)
    A.same({ seen[1].event, seen[1][3] }, { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 7384 })
  end)
end

-- Slice 5: a hot reload in the middle of a Blizzard keeps the area and the cooldown.
local function test_a_reload_mid_blizzard_keeps_the_area_and_the_cooldown()
  SessionH.withSession({ sim = { class = "MAGE" } }, function(sess)
    local w = sess.w
    dummyAt(w, 0, 10)
    _G.UseAction(3)
    sess.s:clickGround(0, 10)
    sess.s:simStep(2.5)
    A.same({ #w.sim.areas, SP.effectsOfKind(w, "ground")[1].radius }, { 1, 8 })
    local cooldown = select(2, SimSpells.cooldown(w, 190356))
    SH.reloaded(sess, function(fresh)
      local fw = fresh.w
      A.same({ #fw.sim.areas, SP.effectsOfKind(fw, "ground")[1].radius }, { 1, 8 })
      A.eq(select(2, SimSpells.cooldown(fw, 190356)) > 0 and select(2, SimSpells.cooldown(fw, 190356)) <= cooldown, true)
    end)
  end)
end

return function()
  test_charge_lands_in_melee_stuns_and_starts_the_fight()
  test_the_mage_casts_fireball_and_drops_a_blizzard()
  test_a_dodge_lights_the_overpower_glow_on_tbc()
  test_a_reload_mid_blizzard_keeps_the_area_and_the_cooldown()
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
