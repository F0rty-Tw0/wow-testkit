-- The Battle.net, instance, guild, chat channel, club, house editor, restriction and template reads WhisperMessenger
-- makes, all from w.mock at call time: bnet = { battleTag }, friends, instance = { type, name, difficultyID,
-- difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, lfgDungeonID,
-- hasWorldTier }, channels = { { name, disabled } } (the id is the position), prefixes, guildClubId, clubs = { { clubId,
-- ... } }, restrictions = { [Enum.AddOnRestrictionType] = Enum.AddOnRestrictionState } and templateInfo = { [name] =
-- info }. Use false to clear the club id a patch set earlier.
local M = {}

local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

-- source: assumed (rows G9, G18) the open world is Eastern Kingdoms with no difficulty; the page says the open-world
-- returns are "nil or otherwise useless", and nothing configured is no club, channel, editor or restriction.
M.DEFAULTS = {
  bnet = { battleTag = "Viewer#1234" },
  friends = 0,
  prefixes = {},
  clubs = {},
  channels = {},
  restrictions = {},
  templateInfo = {},
  instance = {
    name = "Eastern Kingdoms",
    difficultyID = 0,
    difficultyName = "",
    maxPlayers = 0,
    dynamicDifficulty = 0,
    isDynamic = false,
    instanceID = 0,
    instanceGroupSize = 0,
  },
}

-- Enum.AddOnRestrictionState.Active
local RESTRICTION_ACTIVE = 2

local function installBattleNet(w)
  -- source: confirmed (row G18) the seven returns; assumed the kit is logged in to Battle.net as presence and toon 1.
  define(w, "BNGetInfo", function()
    return 1, w.mock.bnet.battleTag, 1, "", false, false, false
  end)
  -- source: assumed (the plan; no page read) the total and online counts; no friend is online in the kit.
  define(w, "BNGetNumFriends", function()
    return w.mock.friends, 0
  end)
end

local function installInstance(w)
  -- source: confirmed (row G9) the eleven returns in this order; instanceType is the type IsInInstance gives.
  define(w, "GetInstanceInfo", function()
    local i = w.mock.instance
    return i.name,
      i.type,
      i.difficultyID,
      i.difficultyName,
      i.maxPlayers,
      i.dynamicDifficulty,
      i.isDynamic,
      i.instanceID,
      i.instanceGroupSize,
      i.lfgDungeonID,
      i.hasWorldTier
  end)
  -- source: assumed (row G18) true with a guild; the mock holds the guild member count.
  define(w, "IsInGuild", function()
    return w.mock.guild.total > 0
  end)
  -- source: assumed (row G18) a guid is in the group when a unit fixture with that guid is flagged inParty or inRaid
  -- (Phase 8's Group.set flags the roster); with no such fixture nobody is listed.
  define(w, "C_PartyInfo.IsGUIDInGroup", function(guid)
    for _, data in pairs(w.unitState and w.unitState.byToken or {}) do
      if data.guid == guid and (data.inParty == true or data.inRaid == true) then
        return true
      end
    end
    return false
  end)
end

local function findChannel(channels, ident)
  if type(ident) == "number" then
    return channels[ident] and ident, channels[ident]
  end
  for id, channel in ipairs(channels) do
    if type(ident) == "string" and channel.name:lower() == ident:lower() then
      return id, channel
    end
  end
end

local function installChannels(w)
  -- source: assumed (the plan; no page read) id, name and disabled for each joined channel, in order.
  define(w, "GetChannelList", function()
    local list = {}
    for id, channel in ipairs(w.mock.channels) do
      list[#list + 1] = id
      list[#list + 1] = channel.name
      list[#list + 1] = channel.disabled == true
    end
    return unpack(list)
  end)
  -- source: assumed (the plan; no page read) id 0 when the channel is not joined; instanceID 0.
  define(w, "GetChannelName", function(ident)
    local id, channel = findChannel(w.mock.channels, ident)
    if not channel then
      return 0
    end
    return id, channel.name, 0
  end)
  define(w, "C_ChatInfo.InChatMessagingLockdown", function()
    return false
  end)
  define(w, "C_ChatInfo.RegisterAddonMessagePrefix", function(prefix)
    local prefixes = w.mock.prefixes
    for _, known in ipairs(prefixes) do
      if known == prefix then
        return true
      end
    end
    prefixes[#prefixes + 1] = prefix
    return true
  end)
end

local function installClubs(w)
  -- source: confirmed (row G18) nil when absent; assumed that the mock holds the guild's club id.
  define(w, "C_Club.GetGuildClubId", function()
    return w.mock.guildClubId or nil
  end)
  define(w, "C_Club.GetSubscribedClubs", function()
    local list = {}
    for i, club in ipairs(w.mock.clubs) do
      list[i] = club
    end
    return list
  end)
  -- source: confirmed (row G18) nil when absent; an id the mock does not hold counts as unscripted.
  define(w, "C_Club.GetClubInfo", function(clubId)
    for _, club in ipairs(w.mock.clubs) do
      if club.clubId == clubId then
        return club
      end
    end
    WorldApi.markUnscripted(w, "C_Club.GetClubInfo")
  end)
end

-- source: confirmed wiki API_Ambiguate: "short" drops the realm, "mail" (and "craftingorder") keep it, the rest drop it
-- only for the player's own realm; assumed (no guild roster) a character on another realm is not in the guild.
local KEEP_REALM = { mail = true, craftingorder = true }

local function installAmbiguate(w)
  define(w, "Ambiguate", function(fullName, context)
    local name, realm = fullName:match("^(.-)%-(.+)$")
    if not name or KEEP_REALM[context] then
      return fullName
    end
    if context == "short" or realm == (w.mock.realm:gsub("[ %-%.]", "")) then
      return name
    end
    return fullName
  end)
end

function M.install(w)
  installAmbiguate(w)
  installBattleNet(w)
  installInstance(w)
  installChannels(w)
  installClubs(w)
  -- source: confirmed (row G18) false for any ordinary value; w.isSecret (Task 8.9) names the secret ones.
  define(w, "issecretvalue", function(value)
    return w.isSecret ~= nil and w.isSecret(value) == true
  end)
  define(w, "C_HouseEditor.IsHouseEditorActive", function()
    return false
  end)
  -- source: confirmed (row G18) a boolean per type; true only for the Active state.
  define(w, "C_RestrictedActions.IsAddOnRestrictionActive", function(restrictionType)
    return w.mock.restrictions[restrictionType] == RESTRICTION_ACTIVE
  end)
  -- source: confirmed (row G18) a table or nothing; assumed that an unknown template is not an error, that the scenario's
  -- templateInfo wins, and that a template an XML file registered (w.ui.virtuals) answers its type (MapCanvasMixin:
  -- GetPinTemplateType, blizzard_mapcanvas.lua:315, makes a pin pool of that type), its <Size> through the inherits
  -- chain (0 for an axis none names; ScrollBoxLinearView.lua:193 reads the extent) and its inherits attribute (row BU15).
  -- keyValues and sourceLocation are not modelled.
  define(w, "C_XMLUtil.GetTemplateInfo", function(name)
    local virtual = w.ui.virtuals[name]
    if w.mock.templateInfo[name] or not virtual then
      return w.mock.templateInfo[name]
    end
    local width, height = virtual.size()
    return { type = virtual.type, width = width or 0, height = height or 0, inherits = virtual.node.attrs.inherits }
  end)
end

return M
