-- Groups: the roster (party and raid tokens, flags, mock fields), GetRaidRosterInfo, UnitGroupRolesAssigned.
local A = require("assert")
local Actors = require("combat_actors")
local Group = require("combat_group")
local H = require("tests.helpers.combat")
local Log = require("combat_log")

local function member(w, name, role)
  return Actors.add(w, { kind = "player", name = name, role = role, level = 80, className = "Warrior", classFile = "WARRIOR" })
end

-- The player and count - 1 more members, in order.
local function roster(w, count)
  local members = { Actors.get(w, "player") }
  for i = 2, count do
    members[i] = member(w, "M" .. i)
  end
  return members
end

local function test_party_roster_answers_and_fires_once() -- (C11)
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local log = H.watch(w, { "GROUP_ROSTER_UPDATE" })
    Group.set(w, { Actors.get(w, "player"), ann }, { raid = false })
    A.eq(#log, 1)
    A.eq(log[1].n, 0)
    A.same({ _G.IsInGroup(), _G.IsInRaid(), _G.GetNumGroupMembers(), _G.GetNumSubgroupMembers() }, { true, false, 2, 1 })
    A.eq(_G.UnitInParty("party1"), true)
    A.eq(_G.UnitGUID("party1"), ann.guid)
  end)
end

local function test_raid_roster_info_has_twelve_values_and_subgroups() -- (C11)
  H.withCombat("retail", function(w)
    local members = roster(w, 7)
    members[6].classFile, members[6].className = "MAGE", "Mage"
    Group.set(w, members, { raid = true })
    local info = { _G.GetRaidRosterInfo(6) }
    A.same(info, { "M6", 0, 2, 80, "Mage", "MAGE", "", true, false, nil, false, "NONE" })
    A.eq(select("#", _G.GetRaidRosterInfo(6)), 12)
    A.eq(select(3, _G.GetRaidRosterInfo(1)), 1)
    A.eq(select(3, _G.GetRaidRosterInfo(5)), 1)
    A.eq(select("#", _G.GetRaidRosterInfo(8)), 0)
    A.same({ _G.IsInRaid(), _G.GetNumGroupMembers(), _G.GetNumSubgroupMembers() }, { true, 7, 4 })
  end)
end

local function test_raid_roster_info_offline_dead_and_leader() -- (C11)
  H.withCombat("retail", function(w)
    local members = roster(w, 3)
    members[2].isConnected, members[2].isDead = false, true
    Group.set(w, members, { raid = true, leader = "raid3" })
    local name, rank, _, level, _, _, zone, online, dead = _G.GetRaidRosterInfo(2)
    A.same({ name, rank, level, zone, online, dead }, { "M2", 0, 0, "Offline", false, true })
    A.eq(select(2, _G.GetRaidRosterInfo(3)), 2)
    A.eq(select(2, _G.GetRaidRosterInfo(1)), 0)
    A.eq(_G.UnitIsGroupLeader("raid3"), true)
    A.eq(_G.UnitIsGroupLeader("player"), false)
  end)
end

local function test_roster_info_is_empty_outside_a_raid() -- (C11)
  H.withCombat("retail", function(w)
    A.eq(select("#", _G.GetRaidRosterInfo(1)), 0)
    Group.set(w, roster(w, 3), { raid = false })
    A.eq(select("#", _G.GetRaidRosterInfo(1)), 0)
  end)
end

local function test_leaving_the_group_clears_party_tokens_and_fires()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Group.set(w, { Actors.get(w, "player"), ann }, { raid = false })
    local log = H.watch(w, { "GROUP_ROSTER_UPDATE" })
    Group.clear(w)
    A.eq(#log, 1)
    A.eq(_G.UnitExists("party1"), false)
    A.eq(_G.IsInGroup(), false)
    A.eq(_G.UnitInParty("player"), false)
    A.eq(ann.inParty, false)
  end)
end

local function test_party_tokens_vanish_in_a_raid_assumed() -- (C11)
  H.withCombat("retail", function(w)
    local members = roster(w, 4)
    Group.set(w, members, { raid = true })
    A.eq(_G.UnitExists("party1"), false)
    A.eq(_G.UnitGUID("raid2"), members[2].guid)
    A.eq(_G.UnitInRaid("raid2"), true)
  end)
end

local function test_party_tokens_bind_in_order_and_pets()
  H.withCombat("retail", function(w)
    local members = roster(w, 3)
    local pet = Actors.add(w, { kind = "pet", name = "Rex" })
    members[3].pet = pet
    Group.set(w, members, { raid = false })
    A.same({ _G.UnitGUID("party1"), _G.UnitGUID("party2") }, { members[2].guid, members[3].guid })
    A.eq(_G.UnitGUID("partypet2"), pet.guid)
    Group.set(w, members, { raid = true })
    A.same({ _G.UnitExists("partypet2"), _G.UnitGUID("raidpet3") }, { false, pet.guid })
  end)
end

local function test_roles_follow_the_actor_and_none_on_role_less_flavours_assumed() -- (C11)
  H.withCombat("retail", function(w)
    local tank = member(w, "Tank", "TANK")
    Group.set(w, { Actors.get(w, "player"), tank }, { raid = false })
    A.same({ _G.UnitGroupRolesAssigned("party1"), _G.UnitGroupRolesAssigned("player") }, { "TANK", "NONE" })
  end)
  H.withCombat("vanilla", function(w)
    local tank = member(w, "Tank", "TANK")
    Group.set(w, { Actors.get(w, "player"), tank }, { raid = false })
    A.eq(_G.UnitGroupRolesAssigned("party1"), "NONE")
  end)
end

local function test_convert_to_raid_keeps_members_and_renumbers()
  H.withCombat("retail", function(w)
    local members = roster(w, 3)
    Group.set(w, members, { raid = false, leader = "party2" })
    local log = H.watch(w, { "GROUP_ROSTER_UPDATE" })
    Group.convertToRaid(w)
    A.eq(#log, 1)
    A.same({ _G.UnitGUID("raid1"), _G.UnitGUID("raid2"), _G.UnitGUID("raid3") }, { members[1].guid, members[2].guid, members[3].guid })
    A.same({ _G.IsInRaid(), _G.UnitExists("party1"), members[2].inRaid }, { true, false, true })
    A.eq(_G.UnitIsGroupLeader("raid3"), true)
    Group.convertToRaid(w)
    A.eq(#log, 1)
  end)
end

local function test_add_and_remove_rewrite_the_roster_and_fire_once_each()
  H.withCombat("retail", function(w)
    local members = roster(w, 3)
    Group.set(w, { members[1], members[2] }, { raid = false })
    local log = H.watch(w, { "GROUP_ROSTER_UPDATE" })
    Group.add(w, members[3])
    A.same({ #log, _G.GetNumGroupMembers(), _G.UnitGUID("party2") }, { 1, 3, members[3].guid })
    Group.remove(w, members[2])
    A.same({ #log, _G.GetNumGroupMembers(), _G.UnitGUID("party1"), _G.UnitExists("party2") }, { 2, 2, members[3].guid, false })
    A.same({ members[2].inParty, members[2].inRaid }, { false, false })
    Group.remove(w, members[3]) -- a group of one disbands
    A.same({ #log, _G.IsInGroup(), w.mock.group }, { 3, false, "none" })
  end)
end

local function test_a_party_holds_five_and_add_needs_a_group()
  H.withCombat("retail", function(w)
    local members = roster(w, 6)
    A.errors(function()
      Group.add(w, members[2])
    end, "no group")
    A.errors(function()
      Group.set(w, members, { raid = false })
    end, "party")
    A.errors(function()
      Group.set(w, { members[2], members[1] }, { raid = false })
    end, "player")
    Group.set(w, { members[1], members[2], members[3], members[4], members[5] }, { raid = false })
    A.errors(function()
      Group.add(w, members[6])
    end, "party")
  end)
end

local function test_a_despawned_member_leaves_the_group()
  H.withCombat("retail", function(w)
    local members = roster(w, 3)
    Group.set(w, members, { raid = false })
    Actors.remove(w, members[2])
    A.same({ _G.GetNumGroupMembers(), _G.UnitGUID("party1") }, { 2, members[3].guid })
    Group.clear(w)
    w:setMock({ group = "party" })
    Actors.remove(w, members[3]) -- no roster to leave: a hand-set mock group is left alone
    A.eq(_G.IsInGroup(), true)
  end)
end

local function test_group_flags_reach_the_log() -- (C5)
  H.withCombat("retail", function(w)
    local members = roster(w, 3)
    Group.set(w, members, { raid = true })
    A.eq((Log.flags(w, members[2])), 0x514)
    Group.set(w, members, { raid = false })
    A.eq((Log.flags(w, members[2])), 0x512)
    Group.clear(w)
    A.eq((Log.flags(w, members[2])), 0x518)
  end)
end

local function test_mock_group_state_still_answers_with_no_roster()
  H.withCombat("retail", function(w)
    w:setMock({ group = "party" })
    A.eq(_G.IsInGroup(), true)
    A.eq(_G.GetNumGroupMembers(), 5)
  end)
end

local function test_is_guid_in_group_follows_the_roster()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    A.eq(_G.C_PartyInfo.IsGUIDInGroup(ann.guid), false)
    Group.set(w, { Actors.get(w, "player"), ann }, { raid = false })
    A.eq(_G.C_PartyInfo.IsGUIDInGroup(ann.guid), true)
    Group.remove(w, ann)
    A.eq(_G.C_PartyInfo.IsGUIDInGroup(ann.guid), false)
  end)
end

local function test_group_set_writes_the_mock_fields()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Group.set(w, { Actors.get(w, "player"), ann }, { raid = false })
    A.same({ w.mock.group, w.mock.groupSize, w.mock.subgroupSize, w.mock.leader }, { "party", 2, 1, "player" })
    Group.set(w, roster(w, 7), { raid = true })
    A.same({ w.mock.group, w.mock.groupSize, w.mock.subgroupSize }, { "raid", 7, 4 })
    Group.clear(w)
    A.same({ w.mock.group, w.mock.groupSize, w.mock.subgroupSize, w.mock.leader }, { "none", false, false, "player" })
  end)
end

return function()
  test_party_roster_answers_and_fires_once()
  test_raid_roster_info_has_twelve_values_and_subgroups()
  test_raid_roster_info_offline_dead_and_leader()
  test_roster_info_is_empty_outside_a_raid()
  test_leaving_the_group_clears_party_tokens_and_fires()
  test_party_tokens_vanish_in_a_raid_assumed()
  test_party_tokens_bind_in_order_and_pets()
  test_roles_follow_the_actor_and_none_on_role_less_flavours_assumed()
  test_convert_to_raid_keeps_members_and_renumbers()
  test_add_and_remove_rewrite_the_roster_and_fire_once_each()
  test_a_party_holds_five_and_add_needs_a_group()
  test_a_despawned_member_leaves_the_group()
  test_group_flags_reach_the_log()
  test_mock_group_state_still_answers_with_no_roster()
  test_is_guid_in_group_follows_the_roster()
  test_group_set_writes_the_mock_fields()
end
