-- Sim loot: the loot tables and their rolls, who rolls on death, and opening the window (LOOT_READY, LOOT_OPENED).
local A = require("assert")
local LH = require("tests.helpers.sim_loot")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local Sim = require("sim")
local SimLoot = require("sim_loot")
local SimMobs = require("sim_mobs")
local SimTarget = require("sim_target")

local K = SimLoot.KIT

local CHANCE_TABLE = {
  money = 0,
  items = {
    { itemID = K.gray, chance = 0.5 },
    { itemID = K.white, chance = 0.5 },
    { itemID = K.gray, chance = 0.5 },
  },
}

-- LOOT_OPENED's payload per flavor: autoLoot, then isFromItem where the manifest lists it (api/<flavor>/Loot.lua).
local OPENED_PAYLOAD = {
  retail = { false, false },
  forever = { false, false },
  mists = { false },
  tbc = { false },
  vanilla = { false },
}

local function test_roll_default_table(w)
  local mob = LH.corpse(w, 0, -8)
  A.same({ mob.lootable, LH.dropList(mob) }, { true, { "money:37", "item:900201x1", "item:900202x2" } })
end

local function test_roll_custom_table(w)
  local mob = LH.corpse(w, 0, -8, { money = 0, items = { { itemID = K.white, count = 3 } } })
  A.same(LH.dropList(mob), { "item:900202x3" })
end

local function test_roll_no_loot(w)
  local mob = LH.corpse(w, 1, -8, false)
  A.same({ mob.lootable, #mob.drops }, { false, 0 })
end

local function test_chance_uses_the_seeded_sequence(w)
  local mob = LH.corpse(w, 0, -8, CHANCE_TABLE)
  A.same(LH.dropList(mob), { "item:900201x1", "item:900202x1" }) -- draws 7.8e-6, 0.1315 pass; 0.7556 fails
  A.eq(w.sim.loot.seed, 1622650073)
end

local function test_reset_restarts_the_chance_sequence(w)
  LH.corpse(w, 0, -8, CHANCE_TABLE)
  Sim.reset(w)
  A.eq(w.sim.loot.seed, 1)
end

local function test_kit_items_are_stored(w)
  A.same({ w.mock.items[K.gray].name, w.mock.items[K.gray].quality, w.mock.items[K.gray].stackCount }, { "Kit Scrap", 0, 5 })
  A.same({ w.mock.items[K.white].name, w.mock.items[K.white].quality, w.mock.items[K.white].stackCount }, { "Kit Linen", 1, 20 })
end

local function test_open_fires_ready_then_opened(w)
  local ev = SH.record(w, LH.LOOT_EVENTS)
  A.eq(SimLoot.open(w, LH.corpse(w, 0, -8)), true)
  A.same(LH.names(ev), { "LOOT_READY", "LOOT_OPENED" })
  A.eq(ev[1][3], false) -- autoLoot off
end

local function test_loot_opened_payload_follows_the_manifest(w)
  local ev = SH.record(w, { "LOOT_OPENED" })
  SimLoot.open(w, LH.corpse(w, 0, -8))
  local payload = { unpack(ev[1], 3, 2 + ev[1][2]) }
  A.same(payload, OPENED_PAYLOAD[w.flavor])
  A.eq(#w.warnings, 0)
end

local function test_too_far(w)
  local ev = SH.record(w, LH.LOOT_EVENTS)
  local errors = SH.record(w, { "UI_ERROR_MESSAGE" })
  local mob = LH.corpse(w, 0, 10) -- 20 yd centre, 17 yd between edges
  A.eq(SimLoot.open(w, mob), false)
  A.same({ #errors, errors[1][4] }, { 1, _G.ERR_LOOT_TOO_FAR })
  A.same({ #ev, w.sim.loot.window }, { 0, nil })
end

local function test_a_living_mob_does_not_open(w)
  local ev = SH.record(w, LH.LOOT_EVENTS)
  local alive = SimMobs.spawn(w, { pos = { x = 0, y = -8 } })
  A.same({ SimLoot.open(w, alive), #ev }, { false, 0 })
end

local function test_a_corpse_without_loot_does_not_open(w)
  local ev = SH.record(w, LH.LOOT_EVENTS)
  A.same({ SimLoot.open(w, LH.corpse(w, 1, -8, false)), #ev }, { false, 0 })
end

local function test_right_click_opens_through_the_action(w)
  local mob = LH.corpse(w, 0, -8)
  A.eq(SimTarget.interact(w, mob, "RightButton"), true)
  A.eq(w.sim.loot.window.guid, mob.guid)
end

local function test_death_listener_rolls_for_a_killed_mob(w, _, player)
  local mob = SimMobs.spawn(w, { pos = { x = 0, y = -8 }, health = 5 })
  A.eq(mob.drops, nil)
  Resolve.damage(w, player, mob, { amount = 100 })
  A.same({ mob.isDead, mob.lootable, #mob.drops }, { true, true, 3 })
end

local function test_a_friend_never_rolls(w)
  local friend = SH.foe(w, 3, -8, { hostile = false })
  Resolve.kill(w, friend)
  A.eq(friend.drops, nil)
end

local function test_a_party_member_never_rolls(w)
  local member = SH.foe(w, 4, -8, { inParty = true })
  Resolve.kill(w, member)
  A.eq(member.drops, nil)
end

local function test_a_raid_member_never_rolls(w)
  local member = SH.foe(w, 4, -8, { inRaid = true })
  Resolve.kill(w, member)
  A.eq(member.drops, nil)
end

local function test_the_player_never_rolls(w, _, player)
  Resolve.kill(w, player)
  A.eq(player.drops, nil)
end

return function()
  for _, flavor in ipairs(LH.FLAVORS) do
    local tests = {
      test_roll_default_table,
      test_roll_custom_table,
      test_roll_no_loot,
      test_chance_uses_the_seeded_sequence,
      test_reset_restarts_the_chance_sequence,
      test_kit_items_are_stored,
      test_open_fires_ready_then_opened,
      test_loot_opened_payload_follows_the_manifest,
      test_too_far,
      test_a_living_mob_does_not_open,
      test_a_corpse_without_loot_does_not_open,
      test_right_click_opens_through_the_action,
      test_death_listener_rolls_for_a_killed_mob,
      test_a_friend_never_rolls,
      test_a_party_member_never_rolls,
      test_a_raid_member_never_rolls,
      test_the_player_never_rolls,
    }
    for _, t in ipairs(tests) do
      SH.withSim(flavor, t)
    end
  end
end
