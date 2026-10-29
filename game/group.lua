-- Combat flags, group state and the instance type, read from w.mock at call time: combat, group ("none", "party" or
-- "raid"), groupSize, subgroupSize, leader and instance.type.
local M = {}

local State = require("game.state")
local Units = require("units")
local WorldApi = require("world_api")
local define = State.define

local PARTY_SIZE = 5
local RAID_SIZE = 10
local RAID_SUBGROUP_SIZE = 4

M.DEFAULTS = {
  combat = false,
  group = "none",
  leader = "player",
  instance = { type = "none" },
}

-- Numeric mock fields use false to clear a value a patch set earlier (State.merge never deletes a key).
local function sizeOr(value, default)
  return type(value) == "number" and value or default
end

-- source: assumed (row G8) GetNumGroupMembers counts the player; the kit's party is 5 and its raid 10.
local function groupSize(mock)
  if mock.group == "party" then
    return sizeOr(mock.groupSize, PARTY_SIZE)
  elseif mock.group == "raid" then
    return sizeOr(mock.groupSize, RAID_SIZE)
  end
  return 0
end

-- source: confirmed (row G8) the other players in the player's own subgroup. A party is one subgroup; the kit's raid
-- subgroup is 4 others unless subgroupSize says otherwise.
local function subgroupSize(mock)
  if mock.group == "party" then
    return groupSize(mock) - 1
  elseif mock.group == "raid" then
    return sizeOr(mock.subgroupSize, RAID_SUBGROUP_SIZE)
  end
  return 0
end

local function installGroup(w)
  define(w, "IsInGroup", function()
    return w.mock.group ~= "none"
  end)
  define(w, "IsInRaid", function()
    return w.mock.group == "raid"
  end)
  define(w, "GetNumGroupMembers", function()
    return groupSize(w.mock)
  end)
  define(w, "GetNumSubgroupMembers", function()
    return subgroupSize(w.mock)
  end)
  -- source: confirmed (row G8) the signature and the meaning; assumed that a solo player leads nothing. The leader's
  -- name stands for the leader's token (row G24).
  define(w, "UnitIsGroupLeader", function(unit)
    return w.mock.group ~= "none" and type(unit) == "string" and Units.standsFor(w, unit, w.mock.leader)
  end)
end

-- source: confirmed (row G8) lockdown and the unit combat flag; lockdown begins after PLAYER_REGEN_DISABLED fires
-- (session_state.lua fires that event before it sets the flag).
local function installCombat(w)
  define(w, "InCombatLockdown", function()
    return w.mock.combat
  end)
  -- The player's name stands for "player" (row G24).
  define(w, "UnitAffectingCombat", function(unit)
    local token = type(unit) == "string" and unit:lower()
    local data, resolved
    if w.unitState then
      data, resolved = Units.fixture(w.unitState, token)
    end
    if token == "player" or resolved == "player" then
      return w.mock.combat or (data ~= nil and data.affectingCombat == true)
    elseif data then
      return data.affectingCombat == true
    end
    WorldApi.markUnscripted(w, "UnitAffectingCombat")
    return false
  end)
end

function M.install(w)
  installGroup(w)
  installCombat(w)
  -- source: confirmed (row G9) isInInstance, instanceType; "none" outside an instance. Assumed: the open-world first
  -- return is false, not nil.
  define(w, "IsInInstance", function()
    local kind = w.mock.instance.type
    return kind ~= "none", kind
  end)
end

return M
