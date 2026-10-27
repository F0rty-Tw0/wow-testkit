-- Combat unit events: the fan-out of actor hooks to unit-token events, and casts, channels and targets.
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local Casts = require("combat_cast")
local H = require("tests.helpers.combat")

local function test_health_fires_once_per_token_in_token_order_assumed() -- (C7)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Actors.bind(w, ann, "target")
    local log = H.watch(w, { "UNIT_HEALTH", "UNIT_MAXHEALTH" })
    Actors.setHealth(w, ann, 400)
    A.same(H.names(log), { "UNIT_HEALTH", "UNIT_HEALTH" })
    A.eq(log[1][3], "party1")
    A.eq(log[2][3], "target")
    Actors.setHealth(w, ann, 400) -- unchanged: no event
    A.eq(#log, 2)
  end)
end

local function test_max_health_event_names_every_token()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local log = H.watch(w, { "UNIT_HEALTH", "UNIT_MAXHEALTH" })
    Actors.setHealthMax(w, ann, 500) -- lowers the health with it
    A.same(H.names(log), { "UNIT_MAXHEALTH", "UNIT_HEALTH" })
    A.eq(log[1][3], "party1")
  end)
end

local function test_aura_update_info_shapes() -- (C8)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local log = H.watch(w, { "UNIT_AURA" })
    local aura = Auras.apply(w, ann, { spellID = H.SPELLS.WARD, absorb = 100 })
    local info = log[1][4]
    A.eq(info.isFullUpdate, false)
    A.eq(info.addedAuras[1].auraInstanceID, aura.auraInstanceID)
    A.eq(info.addedAuras[1].absorb, nil) -- the addon's copy has no kit fields
    Auras.setStacks(w, ann, aura, 2)
    A.same(log[2][4].updatedAuraInstanceIDs, { aura.auraInstanceID })
    Auras.remove(w, ann, aura)
    A.same(log[3][4].removedAuraInstanceIDs, { aura.auraInstanceID })
  end)
end

local function test_absorb_event_follows_the_absorb_total()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local log = H.watch(w, { "UNIT_ABSORB_AMOUNT_CHANGED" })
    Auras.apply(w, ann, { spellID = H.SPELLS.CURSE }) -- no absorb: the total stays 0
    A.eq(#log, 0)
    local ward = Auras.apply(w, ann, { spellID = H.SPELLS.WARD, absorb = 100 })
    A.eq(#log, 1)
    A.eq(log[1][3], "party1")
    Auras.remove(w, ann, ward)
    A.eq(#log, 2)
  end)
end

local function test_power_event_carries_the_power_type()
  H.withCombat("retail", function(w)
    local ann = Actors.add(w, { kind = "player", name = "Ann", token = "party1", power = 100 })
    local log = H.watch(w, { "UNIT_POWER_UPDATE" })
    Actors.setPower(w, ann, 40)
    A.same({ log[1][3], log[1][4] }, { "party1", "MANA" })
  end)
end

local function test_flags_event_names_every_token()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Actors.setDead(w, ann, true)
    local log = H.watch(w, { "UNIT_FLAGS" })
    Actors.setDead(w, ann, false)
    A.same({ #log, log[1][3] }, { 1, "party1" })
  end)
end

local function test_cast_sequence_start_succeeded_stop_assumed() -- (C9)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local log = H.watch(w, { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP" })
    Casts.begin(w, ann, { spellID = H.SPELLS.BOLT })
    Casts.finish(w, ann)
    A.same(H.names(log), { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP" })
    A.truthy(log[1][4]:match("^Cast%-3%-4001%-"))
    A.eq(log[1][5], 900002)
    A.eq(log[2][4], log[1][4])
    A.eq(log[1].n, 4) -- (C9) unit, castGUID, spellID, castBarID
  end)
end

local function test_interrupt_carries_the_interrupter()
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local log = H.watch(w, { "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_STOP" })
    Casts.begin(w, ann, { spellID = H.SPELLS.BOLT })
    Casts.interrupt(w, ann, brute)
    A.same(H.names(log), { "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_STOP" })
    A.eq(log[1][6], brute.guid) -- (C9) unit, castGUID, spellID, interruptedBy, castBarID
    A.eq(log[1].n, 5)
    A.eq(ann.cast, nil)
  end)
end

local function test_fail_fires_failed_then_stop_assumed() -- (C9)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local log = H.watch(w, { "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_STOP" })
    Casts.begin(w, ann, { spellID = H.SPELLS.BOLT })
    Casts.fail(w, ann)
    A.same(H.names(log), { "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_STOP" })
    A.eq(ann.cast, nil)
  end)
end

local function test_unit_casting_info_reflects_the_cast()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local seen
    local frame = _G.CreateFrame("Frame")
    frame:RegisterEvent("UNIT_SPELLCAST_START")
    frame:SetScript("OnEvent", function()
      seen = { _G.UnitCastingInfo("party1") }
    end)
    Casts.begin(w, ann, { spellID = H.SPELLS.BOLT })
    A.eq(seen[1], "Kit Bolt")
    A.eq(seen[5] - seen[4], 2000)
    A.eq(seen[7], ann.cast.castID)
    A.eq(seen[9], 900002)
    Casts.finish(w, ann)
    A.eq(_G.UnitCastingInfo("party1"), nil)
  end)
end

local function test_a_cast_needs_a_duration_from_scenario_data()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local ok, err = pcall(Casts.begin, w, ann, { spellID = H.SPELLS.STRIKE })
    A.eq(ok, false)
    A.contains(err, "duration")
    Casts.begin(w, ann, { spellID = H.SPELLS.STRIKE, duration = 1.5 })
    A.eq(ann.cast.endTimeMs - ann.cast.startTimeMs, 1500)
  end)
end

local function test_a_second_cast_while_casting_raises()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Casts.begin(w, ann, { spellID = H.SPELLS.BOLT })
    local ok, err = pcall(Casts.begin, w, ann, { spellID = H.SPELLS.BOLT })
    A.eq(ok, false)
    A.contains(err, "already casting")
  end)
end

local function test_channel_sets_unit_channel_info_assumed() -- (C9)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local log = H.watch(w, { "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" })
    Casts.channel(w, ann, { spellID = H.SPELLS.BOLT, duration = 3 })
    A.eq(H.names(log)[1], "UNIT_SPELLCAST_CHANNEL_START")
    local name, _, _, start, finish, _, _, spellId = _G.UnitChannelInfo("party1")
    A.same({ name, finish - start, spellId }, { "Kit Bolt", 3000, 900002 })
    Casts.stopChannel(w, ann)
    A.eq(H.names(log)[2], "UNIT_SPELLCAST_CHANNEL_STOP")
    A.eq(log[2][4], log[1][4]) -- the same castGUID
    A.eq(log[2].n, 5) -- unit, castGUID, spellID, interruptedBy, castBarID
    A.eq(_G.UnitChannelInfo("party1"), nil)
  end)
end

local function test_channel_stop_names_the_interrupter()
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local log = H.watch(w, { "UNIT_SPELLCAST_CHANNEL_STOP" })
    Casts.channel(w, ann, { spellID = H.SPELLS.BOLT, duration = 3 })
    Casts.stopChannel(w, ann, brute)
    A.eq(log[1][6], brute.guid)
  end)
end

local function test_target_change_order_assumed() -- (C7)
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    local player = Actors.get(w, "player")
    local log = H.watch(w, { "PLAYER_TARGET_CHANGED", "UNIT_TARGET" })
    Actors.setTarget(w, player, brute)
    A.same(H.names(log), { "PLAYER_TARGET_CHANGED", "UNIT_TARGET" })
    A.eq(log[2][3], "player")
    A.eq(player.targetGuid, brute.guid)
    A.truthy(_G.UnitIsUnit("target", "boss1"))
    Actors.setTarget(w, player, brute) -- unchanged: no event
    A.eq(#log, 2)
    Actors.setTarget(w, player, nil)
    A.eq(_G.UnitExists("target"), false)
    A.eq(player.targetGuid, nil)
  end)
end

local function test_an_npc_target_change_fires_unit_target_only()
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local log = H.watch(w, { "PLAYER_TARGET_CHANGED", "UNIT_TARGET" })
    Actors.setTarget(w, brute, ann)
    A.same(H.names(log), { "UNIT_TARGET" })
    A.eq(log[1][3], "boss1")
  end)
end

local function test_events_fire_on_every_flavor()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "forever", "retail" }) do
    H.withCombat(flavor, function(w)
      local ann = H.pair(w)
      local log = H.watch(w, { "UNIT_HEALTH", "UNIT_AURA", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP" })
      Actors.setHealth(w, ann, 10)
      Auras.apply(w, ann, { spellID = H.SPELLS.WARD })
      Casts.begin(w, ann, { spellID = H.SPELLS.BOLT })
      Casts.fail(w, ann)
      A.eq(#log, 4)
      A.eq(#w.warnings, 0)
    end)
  end
end

return function()
  test_health_fires_once_per_token_in_token_order_assumed()
  test_max_health_event_names_every_token()
  test_aura_update_info_shapes()
  test_absorb_event_follows_the_absorb_total()
  test_power_event_carries_the_power_type()
  test_flags_event_names_every_token()
  test_cast_sequence_start_succeeded_stop_assumed()
  test_interrupt_carries_the_interrupter()
  test_fail_fires_failed_then_stop_assumed()
  test_unit_casting_info_reflects_the_cast()
  test_a_cast_needs_a_duration_from_scenario_data()
  test_a_second_cast_while_casting_raises()
  test_channel_sets_unit_channel_info_assumed()
  test_channel_stop_names_the_interrupter()
  test_target_change_order_assumed()
  test_an_npc_target_change_fires_unit_target_only()
  test_events_fire_on_every_flavor()
end
