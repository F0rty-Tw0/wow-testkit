-- Combat flag, group counts, group leader and instance type, all read from w.mock.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local function test_solo_defaults() -- (G8)
  G.withGame("retail", function()
    A.same({ _G.IsInGroup(), _G.IsInRaid(), _G.GetNumGroupMembers(), _G.GetNumSubgroupMembers() }, { false, false, 0, 0 })
    A.same({ _G.InCombatLockdown(), _G.UnitAffectingCombat("player") }, { false, false })
  end)
end

local function test_party_and_raid_counts_assumed() -- (G8)
  G.withGame("retail", function(w)
    w:setMock({ group = "party" })
    A.same({ _G.IsInGroup(), _G.IsInRaid(), _G.GetNumGroupMembers(), _G.GetNumSubgroupMembers() }, { true, false, 5, 4 })
    w:setMock({ group = "raid", groupSize = 20 })
    A.same({ _G.IsInGroup(), _G.IsInRaid(), _G.GetNumGroupMembers(), _G.GetNumSubgroupMembers() }, { true, true, 20, 4 })
    w:setMock({ groupSize = false, subgroupSize = 2 })
    A.same({ _G.GetNumGroupMembers(), _G.GetNumSubgroupMembers() }, { 10, 2 })
  end)
end

local function test_combat_flag_and_unit_flag() -- (G8)
  G.withGame("retail", function(w)
    w:setMock({ combat = true })
    w:unit("target", { affectingCombat = true })
    w:unit("focus", {})
    A.same({ _G.InCombatLockdown(), _G.UnitAffectingCombat("player"), _G.UnitAffectingCombat("target") }, { true, true, true })
    A.eq(_G.UnitAffectingCombat("focus"), false)
    w:setMock({ combat = false })
    A.same({ _G.InCombatLockdown(), _G.UnitAffectingCombat("player"), _G.UnitAffectingCombat("target") }, { false, false, true })
  end)
end

local function test_player_flag_counts_without_lockdown() -- (G8)
  G.withGame("retail", function(w)
    w:unit("player", { affectingCombat = true })
    A.same({ _G.InCombatLockdown(), _G.UnitAffectingCombat("player") }, { false, true })
  end)
end

local function test_leader_follows_the_mock() -- (G8)
  G.withGame("retail", function(w)
    A.eq(_G.UnitIsGroupLeader("player"), false)
    w:setMock({ group = "party", leader = "party1" })
    A.same({ _G.UnitIsGroupLeader("player"), _G.UnitIsGroupLeader("party1") }, { false, true })
    w:setMock({ leader = "player" })
    A.eq(_G.UnitIsGroupLeader("player"), true)
  end)
end

local function test_in_instance_reads_the_instance_type() -- (G9)
  G.withGame("retail", function(w)
    A.same({ _G.IsInInstance() }, { false, "none" })
    w:setMock({ instance = { type = "party" } })
    A.same({ _G.IsInInstance() }, { true, "party" })
  end)
end

local function test_group_state_answers_on_every_flavor() -- (G8)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function(w)
      w:setMock({ group = "raid" })
      A.same({ _G.IsInGroup(), _G.IsInRaid(), _G.GetNumGroupMembers() }, { true, true, 10 })
    end)
  end
end

return function()
  test_solo_defaults()
  test_party_and_raid_counts_assumed()
  test_combat_flag_and_unit_flag()
  test_player_flag_counts_without_lockdown()
  test_leader_follows_the_mock()
  test_in_instance_reads_the_instance_type()
  test_group_state_answers_on_every_flavor()
end
