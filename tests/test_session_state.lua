-- Session mock state: modifier keys, combat and group flags answered by the kit's API implementations, the events a
-- changed flag fires, merged patches, and the event list the viewer's Fire form reads.
local A = require("assert")
local H = require("tests.helpers.session")

local function textOf(sess)
  return H.item(sess:call("snapshot"), "SessionDemoText").text
end

-- A frame registered for events; returns a reader of { count, last }.
local function listener(events)
  local seen = { count = 0 }
  local frame = _G.CreateFrame("Frame")
  for _, event in ipairs(events) do
    frame:RegisterEvent(event)
  end
  frame:SetScript("OnEvent", function(_, event)
    seen.count, seen.last = seen.count + 1, event
  end)
  return seen
end

-- source: confirmed (row G8) wiki API_InCombatLockdown: "Combat lockdown begins after the PLAYER_REGEN_DISABLED event
-- fires, and ends before the PLAYER_REGEN_ENABLED event fires."
local function test_lockdown_is_off_inside_both_regen_handlers()
  H.withSession(nil, function(sess)
    local inside = {}
    local frame = _G.CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
      inside[event] = _G.InCombatLockdown()
    end)
    sess:call("state", { combat = true })
    A.same({ inside.PLAYER_REGEN_DISABLED, _G.InCombatLockdown() }, { false, true })
    sess:call("state", { combat = false })
    A.same({ inside.PLAYER_REGEN_ENABLED, _G.InCombatLockdown() }, { false, false })
  end)
end

local function test_modifiers_answer_the_key_state()
  H.withSession(nil, function(sess)
    A.eq(sess:call("state", { modifiers = { shift = true } }).ok, true)
    A.same({ _G.IsShiftKeyDown(), _G.IsModifierKeyDown(), _G.IsControlKeyDown(), _G.IsAltKeyDown() }, { true, true, false, false })
    sess:call("state", { modifiers = { shift = false, alt = true } })
    A.same({ _G.IsShiftKeyDown(), _G.IsAltKeyDown(), _G.IsModifierKeyDown() }, { false, true, true })
    sess:call("state", { modifiers = { alt = false } })
    A.eq(_G.IsModifierKeyDown(), false)
  end)
end

local function test_combat_flag_fires_events_once()
  H.withSession(nil, function(sess)
    local seen = listener({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    A.eq(_G.InCombatLockdown(), false)
    sess:call("state", { combat = true })
    A.eq(_G.InCombatLockdown(), true)
    A.eq(textOf(sess), "event:PLAYER_REGEN_DISABLED")
    A.eq(seen.count, 1)
    sess:call("state", { combat = true })
    A.eq(seen.count, 1)
    sess:call("state", { combat = false })
    A.same({ seen.count, seen.last, _G.InCombatLockdown() }, { 2, "PLAYER_REGEN_ENABLED", false })
  end)
end

local function test_group_state_answers_and_fires()
  H.withSession(nil, function(sess)
    local seen = listener({ "GROUP_ROSTER_UPDATE" })
    A.same({ _G.IsInGroup(), _G.IsInRaid() }, { false, false })
    sess:call("state", { group = "raid" })
    A.same({ _G.IsInGroup(), _G.IsInRaid(), seen.count }, { true, true, 1 })
    sess:call("state", { group = "raid" })
    A.eq(seen.count, 1)
    sess:call("state", { group = "party" })
    A.same({ _G.IsInGroup(), _G.IsInRaid(), seen.count }, { true, false, 2 })
    sess:call("state", { group = "none" })
    A.same({ _G.IsInGroup(), _G.IsInRaid() }, { false, false })
    A.contains(sess:call("state", { group = "guild" }).error, "group")
  end)
end

local function test_state_merges_and_returns_the_whole_state()
  H.withSession(nil, function(sess)
    sess:call("state", { units = { target = { name = "Bob" } } })
    local reply = sess:call("state", { modifiers = { ctrl = true } })
    A.eq(reply.ok, true)
    A.eq(reply.state.units.target.name, "Bob")
    A.same(reply.state.modifiers, { shift = false, ctrl = true, alt = false })
    A.same({ reply.state.combat, reply.state.group }, { false, "none" })
    local bad = sess:call("state", { modifiers = { bogus = true } })
    A.eq(bad.ok, false)
    A.contains(bad.error, "bogus")
    A.eq(_G.IsControlKeyDown(), true)
  end)
end

local function test_empty_state_patch_reads_without_a_change()
  H.withSession(nil, function(sess)
    local reply = sess:call("state", {})
    A.eq(reply.ok, true)
    A.eq(reply.state.group, "none")
    A.eq(sess.seq, 0)
  end)
end

local function test_events_lists_payload_names()
  H.withSession(nil, function(sess)
    local events = sess:call("events").events
    local names, payload = {}, nil
    for i, event in ipairs(events) do
      names[i] = event.name
      if event.name == "PLAYER_ENTERING_WORLD" then
        payload = event.payload
      end
    end
    A.same({ payload[1].name, payload[2].name }, { "isInitialLogin", "isReloadingUi" })
    A.same({ payload[1].type, payload[1].nilable }, { "boolean", false })
    local sorted = { unpack(names) }
    table.sort(sorted)
    A.same(names, sorted)
    A.contains(names, "PLAYER_REGEN_DISABLED")
  end)
end

local function test_state_shares_the_game_mock_and_its_key_readers()
  H.withSession(nil, function(sess)
    A.same({ _G.GetLocale(), sess.w.mock.modifiers }, { "enUS", { shift = false, ctrl = false, alt = false } })
    sess.w:setMock({ modifiers = { rshift = true } })
    A.same({ _G.IsShiftKeyDown(), _G.IsRightShiftKeyDown(), _G.IsLeftShiftKeyDown() }, { true, true, false })
    sess:call("state", { modifiers = { ctrl = true } })
    A.same({ _G.IsControlKeyDown(), _G.IsShiftKeyDown() }, { true, true })
  end)
end

-- The combat world sets combat and the group itself, so the state read reports the world's flags, not the last patch.
local function test_state_read_follows_the_combat_world()
  H.withSession(nil, function(sess)
    A.eq(sess:call("combat", { action = "preset", name = "dungeon" }).ok, true)
    A.eq(sess:call("combat", { action = "pull" }).ok, true)
    local state = sess:call("state", {}).state
    A.same({ state.combat, state.group }, { true, "party" })
  end)
end

return function()
  test_modifiers_answer_the_key_state()
  test_combat_flag_fires_events_once()
  test_lockdown_is_off_inside_both_regen_handlers()
  test_group_state_answers_and_fires()
  test_state_merges_and_returns_the_whole_state()
  test_empty_state_patch_reads_without_a_change()
  test_events_lists_payload_names()
  test_state_shares_the_game_mock_and_its_key_readers()
  test_state_read_follows_the_combat_world()
end
