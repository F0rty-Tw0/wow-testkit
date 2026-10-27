-- Combat log: payload packing per subevent, object flags, timestamps, the ring and delivery to addons.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.combat")
local Log = require("combat_log")

local CLEU = "COMBAT_LOG_EVENT_UNFILTERED"

-- Registers CLEU on frame from addon context (no tail call: it would drop the chunk from the stack).
local function registerAsAddon(w, frame)
  local chunk = assert(loadstring("frame:RegisterEvent('" .. CLEU .. "')", "@addon:T/Test.lua"))
  setfenv(chunk, { frame = frame })
  w:callAsAddon(chunk)
end

local function test_spell_damage_payload_order() -- (C1, C2, C3)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local got = Log.emit(w, "SPELL_DAMAGE", ann, brute, { spellID = H.SPELLS.STRIKE, amount = 120, overkill = -1 })
    A.eq(got[2], "SPELL_DAMAGE")
    A.eq(got[3], false) -- hideCaster
    A.same({ got[4], got[5], got[8], got[9] }, { ann.guid, "Ann", brute.guid, "Brute" })
    A.same({ got[12], got[13], got[14] }, { 900001, "Kit Strike", 1 }) -- spellId, spellName, spellSchool
    A.same({ got[15], got[16], got[17] }, { 120, -1, 1 }) -- amount, overkill, school
    A.eq(got.n, 24) -- eleven base, three spell, ten damage fields
  end)
end

local function test_swing_damage_has_no_spell_prefix() -- (C2)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local got = Log.emit(w, "SWING_DAMAGE", brute, ann, { amount = 80 })
    A.same({ got[12], got[13], got[14] }, { 80, 0, 1 }) -- amount, overkill (a number), school (physical)
    A.same({ got.n, got[21] }, { 21, false }) -- isOffHand is the last field
  end)
end

local function test_environmental_damage_has_no_off_hand() -- (C3)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local got = Log.emit(w, "ENVIRONMENTAL_DAMAGE", nil, ann, { environmentalType = "Lava", amount = 50 })
    A.same({ got.n, got[12], got[13] }, { 21, "Lava", 50 })
  end)
end

local function test_missed_immune_payload() -- (C3)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local got = Log.emit(w, "SPELL_MISSED", ann, brute, { spellID = H.SPELLS.BOLT, missType = "IMMUNE" })
    A.same({ got[15], got[16] }, { "IMMUNE", false })
  end)
end

local function test_heal_payload() -- (C3)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local got = Log.emit(w, "SPELL_HEAL", ann, ann, { spellID = H.SPELLS.MEND, amount = 300 })
    A.same({ got[15], got[16] }, { 300, 0 })
  end)
end

local function test_aura_applied_carries_the_aura_type() -- (C3)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local buff = Log.emit(w, "SPELL_AURA_APPLIED", ann, ann, { spellID = H.SPELLS.WARD, auraType = "BUFF", remainingPoints = 200 })
    local debuff = Log.emit(w, "SPELL_AURA_APPLIED", brute, ann, { spellID = H.SPELLS.CURSE, auraType = "DEBUFF" })
    A.same({ buff[15], buff[16], debuff[15], debuff[16] }, { "BUFF", 200, "DEBUFF", nil })
  end)
end

local function test_cast_success_without_a_destination_assumed() -- (C4)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local got = Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.STRIKE })
    A.same({ got[8], got[9], got[10], got[11] }, { "", nil, 0, 0 })
  end)
end

-- source: confirmed (row C4) the wiki's UNIT_DIED example has source GUID "0000000000000000", no name and flags
-- 0x80000000.
local function test_unit_died_has_the_dying_unit_as_destination() -- (C3, C4)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local got = Log.emit(w, "UNIT_DIED", nil, ann)
    A.same({ got[4], got[5], got[6], got[7] }, { "0000000000000000", nil, 0x80000000, 0x80000000 })
    A.same({ got[8], got[9] }, { ann.guid, "Ann" })
    A.same({ got[12], got[13], got.n }, { 0, false, 13 }) -- recapID, unconsciousOnDeath
  end)
end

local function test_interrupt_and_dispel_carry_the_extra_spell() -- (C3)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local interrupt = Log.emit(w, "SPELL_INTERRUPT", ann, brute, { spellID = H.SPELLS.STRIKE, extraSpellID = H.SPELLS.BOLT })
    A.same({ interrupt[15], interrupt[16], interrupt[17], interrupt.n }, { 900002, "Kit Bolt", 4, 17 })
    local dispel = Log.emit(w, "SPELL_DISPEL", ann, brute, { spellID = H.SPELLS.STRIKE, extraSpellID = H.SPELLS.CURSE, auraType = "DEBUFF" })
    A.same({ dispel[15], dispel[18] }, { 900005, "DEBUFF" })
  end)
end

local function test_spell_absorbed_layout() -- (C3)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local spell = Log.emit(w, "SPELL_ABSORBED", brute, ann, { spellID = H.SPELLS.BOLT, caster = ann, absorbSpellID = H.SPELLS.WARD, amount = 90 })
    A.same({ spell[12], spell[15], spell[16], spell[19], spell[20], spell[22], spell.n }, { 900002, ann.guid, "Ann", 900004, "Kit Ward", 90, 23 })
    local swing = Log.emit(w, "SPELL_ABSORBED", brute, ann, { caster = ann, absorbSpellID = H.SPELLS.WARD, amount = 90 })
    A.same({ swing[12], swing[13], swing[16], swing[19], swing.n }, { ann.guid, "Ann", 900004, 90, 20 })
  end)
end

local function test_object_flags_per_actor_kind() -- (C5)
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    local player = Actors.get(w, "player")
    A.same({ Log.flags(w, player) }, { 0x511, 0 })
    ann.inParty = true
    A.eq((Log.flags(w, ann)), 0x512)
    ann.inRaid = true
    A.eq((Log.flags(w, ann)), 0x514)
    A.eq((Log.flags(w, brute)), 0xA48)
    local friendlyNpc = Actors.add(w, { kind = "npc", name = "Clerk" })
    A.eq((Log.flags(w, friendlyNpc)), 0xA18) -- assumed: outsider, friendly, control npc, type npc
  end)
end

local function test_target_focus_and_raid_icon_flags()
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    local player = Actors.get(w, "player")
    Actors.setTarget(w, player, brute)
    brute.raidTarget = 8
    A.same({ Log.flags(w, brute) }, { 0x10A48, 0x80 }) -- row C5: with the current target bit
    Actors.bind(w, brute, "focus")
    A.eq((Log.flags(w, brute)), 0x30A48)
  end)
end

local function test_timestamps_follow_the_world_clock()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local first = Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.STRIKE })
    w:advance(2.5)
    local second = Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.STRIKE })
    A.eq(second[1] - first[1], 2.5)
    A.eq(first[1], 1790000000)
    w:setMock({ serverTime = 5000 })
    local third = Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.STRIKE })
    A.eq(third[1], 5002.5)
    A.eq(_G.GetServerTime(), 5002)
  end)
end

local function test_spell_name_and_school_default_from_the_spell_data()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local got = Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = 999 })
    A.same({ got[12], got[13], got[14] }, { 999, "Spell 999", 1 })
    local given = Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.BOLT, spellName = "Renamed", spellSchool = 8 })
    A.same({ given[13], given[14] }, { "Renamed", 8 })
  end)
end

local function test_emit_rejects_a_misuse()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    A.errors(function()
      Log.emit(w, "SPELL_NONSENSE", ann, nil, {})
    end, "unknown subevent")
    A.errors(function()
      Log.emit(w, "SPELL_DAMAGE", ann, nil, { amount = 1 })
    end, "spellID")
    A.errors(function()
      Log.emit(w, "SPELL_DAMAGE", ann, nil, { spellID = 1, amout = 1 })
    end, "unknown field 'amout'")
  end)
end

local function test_info_outside_a_handler_returns_nothing_assumed()
  H.withCombat("vanilla", function(w)
    local ann = H.pair(w)
    Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.STRIKE })
    A.eq(select("#", _G.CombatLogGetCurrentEventInfo()), 0)
  end)
end

-- source: confirmed (row C18) the bare accessor and C_CombatLog.GetCurrentEventInfo exist on vanilla, mists and tbc and
-- not on retail or forever.
local function test_accessors_follow_the_flavor_api_data()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists" }) do
    H.withCombat(flavor, function(w)
      local ann = H.pair(w)
      local seen
      H.onLog(w, function(...)
        seen = { n = select("#", ...), ... }
        seen.viaNamespace = { _G.C_CombatLog.GetCurrentEventInfo() }
      end)
      Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.STRIKE })
      A.same({ seen[2], seen.n }, { "SPELL_CAST_SUCCESS", 14 })
      A.same(seen.viaNamespace, { unpack(seen, 1, seen.n) })
    end)
  end
  for _, flavor in ipairs({ "retail", "forever" }) do
    H.withCombat(flavor, function()
      A.same({ _G.CombatLogGetCurrentEventInfo, (_G.C_CombatLog or {}).GetCurrentEventInfo }, {})
    end)
  end
end

local function test_cleu_reaches_addons_on_classic()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "forever" }) do
    H.withCombat(flavor, function(w)
      local ann, brute = H.pair(w)
      local frame = _G.CreateFrame("Frame")
      local args
      frame:SetScript("OnEvent", function(_, event, ...)
        args = { event = event, n = select("#", ...) }
      end)
      registerAsAddon(w, frame)
      Log.emit(w, "SWING_DAMAGE", brute, ann, { amount = 5 })
      A.same(args, { event = CLEU, n = 0 }) -- the payload is read through the accessor, not passed
    end)
  end
end

local function test_cleu_register_is_forbidden_on_retail_and_the_kit_log_still_fills()
  H.withCombat("retail", function(w, c)
    local ann, brute = H.pair(w)
    local frame = _G.CreateFrame("Frame")
    local count = 0
    frame:SetScript("OnEvent", function()
      count = count + 1
    end)
    registerAsAddon(w, frame)
    Log.emit(w, "SWING_DAMAGE", brute, ann, { amount = 5 })
    A.same({ count, c.log.seq, #c.log.entries }, { 0, 1, 1 })
    A.eq(c.log.entries[1][2], "SWING_DAMAGE")
  end)
end

local function test_ring_keeps_the_newest_1000_and_counts_all()
  H.withCombat("retail", function(w, c)
    local ann = H.pair(w)
    for i = 1, 1005 do
      Log.emit(w, "SWING_DAMAGE", ann, nil, { amount = i })
    end
    A.same({ #c.log.entries, c.log.seq }, { 1000, 1005 })
    A.same({ c.log.entries[1].seq, c.log.entries[1][12], c.log.entries[1000][12] }, { 6, 6, 1005 })
  end)
end

local function test_handler_error_is_recorded_and_the_next_event_still_fires()
  H.withCombat("vanilla", function(w)
    local ann = H.pair(w)
    local after = 0
    H.onLog(w, function()
      error("boom")
    end)
    H.onLog(w, function()
      after = after + 1
    end)
    Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.STRIKE })
    Log.emit(w, "SPELL_CAST_SUCCESS", ann, nil, { spellID = H.SPELLS.STRIKE })
    A.same({ #w.errors, after }, { 2, 2 })
    A.eq(select("#", _G.CombatLogGetCurrentEventInfo()), 0) -- current is cleared even after errors
  end)
end

local function test_object_flag_globals_are_installed_when_absent()
  H.withCombat("retail", function()
    A.same({ _G.COMBATLOG_OBJECT_TYPE_PLAYER, _G.COMBATLOG_OBJECT_REACTION_HOSTILE, _G.COMBATLOG_OBJECT_RAIDTARGET8 }, { 0x400, 0x40, 0x80 })
  end)
end

return function()
  test_spell_damage_payload_order()
  test_swing_damage_has_no_spell_prefix()
  test_environmental_damage_has_no_off_hand()
  test_missed_immune_payload()
  test_heal_payload()
  test_aura_applied_carries_the_aura_type()
  test_cast_success_without_a_destination_assumed()
  test_unit_died_has_the_dying_unit_as_destination()
  test_interrupt_and_dispel_carry_the_extra_spell()
  test_spell_absorbed_layout()
  test_object_flags_per_actor_kind()
  test_target_focus_and_raid_icon_flags()
  test_timestamps_follow_the_world_clock()
  test_spell_name_and_school_default_from_the_spell_data()
  test_emit_rejects_a_misuse()
  test_info_outside_a_handler_returns_nothing_assumed()
  test_accessors_follow_the_flavor_api_data()
  test_cleu_reaches_addons_on_classic()
  test_cleu_register_is_forbidden_on_retail_and_the_kit_log_still_fills()
  test_ring_keeps_the_newest_1000_and_counts_all()
  test_handler_error_is_recorded_and_the_next_event_still_fires()
  test_object_flag_globals_are_installed_when_absent()
end
