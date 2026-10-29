-- C_ClassTalents and C_Traits over w.mock.traits (B6, B7, B13): { configID, configs = { [configID] = { name, type, treeIDs,
-- usesSharedActionBars } }, trees = { [treeID] = { nodes = { nodeID, ... }, currencies = { TreeCurrencyInfo, ... } } },
-- nodes = { [nodeID] = TraitNodeInfo fields }, entries = { [entryID] = TraitEntryInfo fields }, definitions = { [definitionID]
-- = TraitDefinitionInfo fields } }, read at call time. Availability, gates and costs are the server's: the store holds
-- them and the node reader defaults only what B7 names.
local M = {}

local Requests = require("game.requests")
local State = require("game.state")
local define = State.define

M.DEFAULTS = { traits = { configs = {}, trees = {}, nodes = {}, entries = {}, definitions = {} } }

-- A deep copy: Blizzard code mutates the tables these readers return, and the store must not see it.
local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, item in pairs(value) do
    out[key] = copy(item)
  end
  return out
end

-- source: assumed (B7) an unset isAvailable, isVisible and meetsEdgeRequirements is true, activeRank and currentRank
-- are ranksPurchased, canPurchaseRank is false; the client reads all of them from the server (R4).
local function nodeInfo(id, node)
  local ranks = node.ranksPurchased or 0
  local entryIDs = node.entryIDs or {}
  local maxRanks = node.maxRanks or 0
  return copy({
    ID = id,
    posX = node.posX or 0,
    posY = node.posY or 0,
    flags = node.flags or 0,
    entryIDs = entryIDs,
    entryIDsWithCommittedRanks = node.entryIDsWithCommittedRanks or {},
    canPurchaseRank = node.canPurchaseRank == true,
    canRefundRank = node.canRefundRank == true,
    isAvailable = node.isAvailable ~= false,
    isVisible = node.isVisible ~= false,
    isDisplayError = node.isDisplayError == true,
    ranksPurchased = ranks,
    ranksIncreased = node.ranksIncreased or 0,
    entryIDToRanksIncreased = node.entryIDToRanksIncreased or {},
    activeRank = node.activeRank or ranks,
    currentRank = node.currentRank or ranks,
    activeEntry = node.activeEntry or (ranks > 0 and entryIDs[1] and { entryID = entryIDs[1], rank = ranks } or nil),
    nextEntry = node.nextEntry,
    maxRanks = maxRanks,
    totalMaxRanks = node.totalMaxRanks or maxRanks,
    type = node.type or 0,
    visibleEdges = node.visibleEdges or {},
    meetsEdgeRequirements = node.meetsEdgeRequirements ~= false,
    groupIDs = node.groupIDs or {},
    conditionIDs = node.conditionIDs or {},
    isCascadeRepurchasable = node.isCascadeRepurchasable == true,
    cascadeRepurchaseEntryID = node.cascadeRepurchaseEntryID,
    subTreeID = node.subTreeID,
    subTreeActive = node.subTreeActive == true,
  })
end

local function installClassTalents(w)
  define(w, "C_ClassTalents.GetActiveConfigID", function()
    return w.mock.traits.configID
  end)
  define(w, "C_ClassTalents.GetConfigIDsBySpecID", function()
    local id = w.mock.traits.configID
    return id and { id } or {}
  end)
  -- source: assumed (B7) the player can edit; the server decides.
  define(w, "C_ClassTalents.CanEditTalents", function()
    return true
  end)
end

local function installTree(w)
  -- source: confirmed (B6) the fields; an invalid configID returns nil (wiki API_C_Traits.GetNodeInfo, assumed alike here).
  define(w, "C_Traits.GetConfigInfo", function(configID)
    local record = w.mock.traits.configs[configID]
    if not record then
      return nil
    end
    return {
      ID = configID,
      type = record.type,
      name = record.name,
      treeIDs = copy(record.treeIDs or {}),
      usesSharedActionBars = record.usesSharedActionBars == true,
    }
  end)
  define(w, "C_Traits.GetTreeInfo", function(configID, treeID)
    local tree = w.mock.traits.configs[configID] and w.mock.traits.trees[treeID]
    if not tree then
      return nil
    end
    return {
      ID = treeID,
      gates = copy(tree.gates or {}),
      hideSingleRankNumbers = tree.hideSingleRankNumbers == true,
      rootNodeID = tree.rootNodeID,
      uiTextureKit = tree.uiTextureKit,
      titleText = tree.titleText,
    }
  end)
  define(w, "C_Traits.GetTreeNodes", function(treeID)
    local tree = w.mock.traits.trees[treeID]
    return copy(tree and tree.nodes or {})
  end)
  define(w, "C_Traits.GetTreeCurrencyInfo", function(_, treeID)
    local tree = w.mock.traits.trees[treeID]
    return copy(tree and tree.currencies or {})
  end)
end

local function installNodes(w)
  -- source: confirmed (B6) a node whose info cannot be retrieved comes back zeroed, so ID 0; assumed that a node id the store
  -- lacks behaves like it.
  define(w, "C_Traits.GetNodeInfo", function(configID, nodeID)
    if not w.mock.traits.configs[configID] then
      return nil
    end
    local node = w.mock.traits.nodes[nodeID]
    return nodeInfo(node and nodeID or 0, node or {})
  end)
  -- source: assumed (B6) the same zeroed answer for an entry the store lacks; a missing definition is nil.
  define(w, "C_Traits.GetEntryInfo", function(configID, entryID)
    if not w.mock.traits.configs[configID] then
      return nil
    end
    local entry = w.mock.traits.entries[entryID] or {}
    return {
      definitionID = entry.definitionID or 0,
      subTreeID = entry.subTreeID,
      type = entry.type or 0,
      maxRanks = entry.maxRanks or 0,
      isAvailable = entry.isAvailable ~= false,
      isDisplayError = entry.isDisplayError == true,
      conditionIDs = copy(entry.conditionIDs or {}),
    }
  end)
  define(w, "C_Traits.GetDefinitionInfo", function(definitionID)
    return copy(w.mock.traits.definitions[definitionID])
  end)
end

-- source: assumed (B13) the client only asks; the server answers with the new ranks and an event.
local function installRequests(w)
  for _, name in ipairs({ "C_Traits.PurchaseRank", "C_Traits.CommitConfig" }) do
    define(w, name, function(...)
      Requests.record(w, name, ...)
      return true
    end)
  end
end

function M.install(w)
  installClassTalents(w)
  installTree(w)
  installNodes(w)
  installRequests(w)
end

return M
