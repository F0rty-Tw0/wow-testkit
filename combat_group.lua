-- Groups: the player's party or raid as a roster of actors. Group.set, add, remove, convertToRaid and clear bind the
-- party#/raid# tokens, mark each actor's inParty and inRaid, write the w.mock fields the group readers answer from (group,
-- groupSize, subgroupSize, leader) and fire GROUP_ROSTER_UPDATE once. Installs GetRaidRosterInfo and UnitGroupRolesAssigned.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local State = require("game.state")
local define = State.define

local unpack = unpack

local PLAYER = "player"
local PARTY_SIZE, RAID_SIZE, SUBGROUP_SIZE = 5, 40, 5
local GROUP_PREFIXES = { "party", "partypet", "raid", "raidpet" }
local OFFLINE_ZONE = "Offline"
-- source: assumed (row C11) the flavors that return only "NONE": no role selection exists before the Wrath client.
local ROLE_LESS = { vanilla = true, tbc = true }

local function isGroupToken(token)
  for _, prefix in ipairs(GROUP_PREFIXES) do
    if token:match("^" .. prefix .. "%d+$") then
      return true
    end
  end
  return false
end

local function unbindGroupTokens(w)
  local tokens = {}
  for token in pairs(w.unitState.byToken) do
    if isGroupToken(token) then
      tokens[#tokens + 1] = token
    end
  end
  for _, token in ipairs(tokens) do
    Actors.unbind(w, token)
  end
end

local function release(actor)
  actor.inParty, actor.inRaid = false, false
end

-- The member a leader token names in a roster of this kind; the player when token is nil.
local function leaderOf(members, raid, token)
  if token == nil or token == PLAYER then
    return members[1]
  end
  local prefix, n = tostring(token):match("^(%a+)(%d+)$")
  local actor = prefix == (raid and "raid" or "party") and members[raid and tonumber(n) or tonumber(n) + 1]
  if not actor then
    error(string.format("Group: leader '%s' names no member of this %s", tostring(token), raid and "raid" or "party"), 3)
  end
  return actor
end

local function check(w, members, raid, name)
  local c = w.combat
  local max = raid and RAID_SIZE or PARTY_SIZE
  if #members < 2 or #members > max then
    error(string.format("Group.%s: a %s holds 2 to %d members, got %d", name, raid and "raid" or "party", max, #members), 3)
  end
  if members[1] ~= w.unitState.byToken[PLAYER] then
    error("Group." .. name .. ": member 1 must be the player", 3)
  end
  local seen = {}
  for _, actor in ipairs(members) do
    if c.actors[actor.guid] ~= actor or seen[actor] then
      error("Group." .. name .. ": every member must be a distinct actor of this world", 3)
    end
    seen[actor] = true
  end
end

-- Rewrites tokens, actor flags and the mock fields from the roster, then fires GROUP_ROSTER_UPDATE.
-- source: confirmed (row C11) the event fires when a group forms, disbands or changes members; assumed (row C11) party#
-- tokens do not exist in a raid, a raid's tokens start at raid1 for the player, and every member is also inParty.
local function commit(w, g)
  unbindGroupTokens(w)
  local prefix = g.raid and "raid" or "party"
  local leaderToken = PLAYER
  for i, actor in ipairs(g.members) do
    actor.inParty, actor.inRaid = true, g.raid
    local index = g.raid and i or i - 1
    if index > 0 then
      Actors.bind(w, actor, prefix .. index)
      if actor.pet then
        Actors.bind(w, actor.pet, prefix .. "pet" .. index)
      end
      if actor == g.leader and i > 1 then
        leaderToken = prefix .. index
      end
    end
  end
  local size = #g.members
  w:setMock({
    group = prefix,
    groupSize = size,
    subgroupSize = (g.raid and math.min(size, SUBGROUP_SIZE) or size) - 1,
    leader = leaderToken,
  })
  Combat.fire(w, "GROUP_ROSTER_UPDATE")
end

-- members = { player, actor, ... } in roster order; opts = { raid = bool, leader = token? } (the player leads by default).
-- An actor's optional pet (an actor) takes the matching partypet# or raidpet# token.
function M.set(w, members, opts)
  opts = opts or {}
  local raid = opts.raid == true
  check(w, members, raid, "set")
  local g = { members = { unpack(members) }, raid = raid, leader = leaderOf(members, raid, opts.leader) }
  for _, actor in ipairs(w.combat.group and w.combat.group.members or {}) do
    release(actor)
  end
  w.combat.group = g
  commit(w, g)
end

local function current(w, name)
  local g = w.combat.group
  if not g then
    error("Group." .. name .. ": no group; call Group.set first", 3)
  end
  return g
end

function M.add(w, actor)
  local g = current(w, "add")
  local max = g.raid and RAID_SIZE or PARTY_SIZE
  if #g.members >= max then
    error(string.format("Group.add: a %s holds %d members%s", g.raid and "raid" or "party", max, g.raid and "" or "; Group.convertToRaid first"), 2)
  end
  local members = { unpack(g.members) }
  members[#members + 1] = actor
  check(w, members, g.raid, "add")
  g.members = members
  commit(w, g)
end

function M.clear(w)
  local g = w.combat.group
  if not g and w.mock.group == "none" then
    return
  end
  for _, actor in ipairs(g and g.members or {}) do
    release(actor)
  end
  w.combat.group = nil
  unbindGroupTokens(w)
  w:setMock({ group = "none", groupSize = false, subgroupSize = false, leader = PLAYER })
  Combat.fire(w, "GROUP_ROSTER_UPDATE")
end

-- Takes actor out of the roster (the player leaving disbands it, as does a roster of one left behind); a leader who
-- leaves hands the lead to the player.
function M.remove(w, actor)
  local g = w.combat.group
  if not g then
    return
  elseif actor == g.members[1] then
    return M.clear(w)
  end
  for i, member in ipairs(g.members) do
    if member == actor then
      table.remove(g.members, i)
      release(actor)
      if #g.members < 2 then
        return M.clear(w)
      end
      g.leader = g.leader == actor and g.members[1] or g.leader
      return commit(w, g)
    end
  end
end

function M.convertToRaid(w)
  local g = current(w, "convertToRaid")
  if not g.raid then
    g.raid = true
    commit(w, g)
  end
end

-- source: confirmed (row C11) the role is TANK, HEALER, DAMAGER or NONE; assumed it is the actor's role field.
local function roleOf(w, actor)
  return not ROLE_LESS[w.flavor] and actor and actor.role or "NONE"
end

function M.install(w)
  Combat.listen(w, "despawn", function(actor)
    M.remove(w, actor)
  end)
  -- source: confirmed (row C11) the twelve returns in order, rank 2 for the leader, none for an index with no member;
  -- assumed (row C11) subgroups of five by index, no assistants, no main tank or assist, level 0 and zone "Offline" for
  -- an actor whose isConnected is false.
  define(w, "GetRaidRosterInfo", function(index)
    local g = w.combat.group
    local actor = g and g.raid and type(index) == "number" and g.members[index]
    if not actor then
      return
    end
    local online = actor.isConnected ~= false
    local level, zone = actor.level, w.mock.zone.zone
    if not online then
      level, zone = 0, OFFLINE_ZONE
    end
    return actor.name,
      actor == g.leader and 2 or 0,
      math.ceil(index / SUBGROUP_SIZE),
      level,
      actor.className,
      actor.classFile,
      zone,
      online,
      actor.isDead == true,
      nil,
      false,
      roleOf(w, actor)
  end)
  define(w, "UnitGroupRolesAssigned", function(unit)
    return roleOf(w, Actors.get(w, unit))
  end)
end

return M
