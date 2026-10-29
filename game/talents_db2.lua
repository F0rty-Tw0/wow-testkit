-- Talent data built from the client extract's DB2 tables (B17): the classic tabs of the player's class and a trait tree's
-- nodes. Kept apart from the readers (game/talents_*.lua), which never touch DB2. Builders return a table for
-- BlizzardData.fill, so scenario data wins key by key and no extract means nil.
local M = {}

local BlizzardData = require("blizzard_data")
local Roster = require("combat_roster_data")

local MAX_SPELL_RANKS = 9

-- The class id of a classFile: the retail class list is in class id order (WARRIOR 1 ... EVOKER 13).
local function classID(classFile)
  for id, file in ipairs(Roster.CLASSES.retail) do
    if file == classFile then
      return id
    end
  end
  return nil
end

-- source: assumed (B17) ClassMask has bit 2^(classID - 1) set for a class the tab belongs to; Lua 5.1 has no bit ops.
local function hasClass(mask, id)
  return math.floor((mask or 0) / 2 ^ (id - 1)) % 2 == 1
end

-- source: assumed (B17) Talent.TierID and ColumnIndex are 0-based, SpellRank holds a spell id per rank (0 = none) and
-- PrereqTalent holds Talent row ids (0 = none) with PrereqRank beside them.
local function talentOf(w, row, talents)
  local spells = {}
  for i = 1, MAX_SPELL_RANKS do
    local id = row.SpellRank and row.SpellRank[i]
    if id and id ~= 0 then
      spells[#spells + 1] = id
    end
  end
  BlizzardData.spells(w, { spells[1] or 0 })
  local spell = w.mock.spells[spells[1]]
  local prereqs = {}
  for i, id in ipairs(row.PrereqTalent or {}) do
    local prereq = id ~= 0 and talents and talents[id]
    if prereq then
      prereqs[#prereqs + 1] = { tier = prereq.TierID + 1, column = prereq.ColumnIndex + 1, rank = row.PrereqRank and row.PrereqRank[i] }
    end
  end
  return {
    talentID = row.ID,
    name = spell and spell.name,
    icon = spell and spell.icon,
    tier = row.TierID + 1,
    column = row.ColumnIndex + 1,
    rank = 0,
    maxRank = #spells,
    spellID = spells[1],
    prereqs = prereqs,
  }
end

local function byOrder(a, b)
  if a.OrderIndex ~= b.OrderIndex then
    return (a.OrderIndex or 0) < (b.OrderIndex or 0)
  end
  return a.ID < b.ID
end

-- { tabs = { ... } } for the tabs of classFile (default: the player's UnitClass) in OrderIndex order, or nil without an
-- extract, a class or a tab. The tab has no icon: it is SpellIconID, an id into a table this phase does not export.
function M.classic(w, classFile)
  local tabs, talents = BlizzardData.table(w, "TalentTab"), BlizzardData.table(w, "Talent")
  local id = classID(classFile or select(2, _G.UnitClass("player")))
  if not (tabs and id) then
    return nil
  end
  local rows = {}
  for _, row in pairs(tabs) do
    if hasClass(row.ClassMask, id) then
      rows[#rows + 1] = row
    end
  end
  table.sort(rows, byOrder)
  local out = {}
  for _, row in ipairs(rows) do
    local tab = { id = row.ID, name = row.Name_lang, description = row.Description_lang, background = row.BackgroundFile, talents = {} }
    for _, talent in ipairs(BlizzardData.rowsBy(w, "Talent", "TabID", row.ID)) do
      tab.talents[#tab.talents + 1] = talentOf(w, talent, talents)
    end
    out[#out + 1] = tab
  end
  return #out > 0 and { tabs = out } or nil
end

local function byIndex(a, b)
  return (a.Index or 0) < (b.Index or 0)
end

-- Adds the entries of one node (TraitNodeXTraitNodeEntry, ordered by Index) and their definitions to the maps; returns the
-- entry ids and the largest MaxRanks.
local function entriesOf(w, nodeID, out)
  local entryTable, definitionTable = BlizzardData.table(w, "TraitNodeEntry"), BlizzardData.table(w, "TraitDefinition")
  local links = BlizzardData.rowsBy(w, "TraitNodeXTraitNodeEntry", "TraitNodeID", nodeID)
  table.sort(links, byIndex)
  local ids, maxRanks = {}, 0
  for _, link in ipairs(links) do
    local entry = entryTable and entryTable[link.TraitNodeEntryID]
    ids[#ids + 1] = link.TraitNodeEntryID
    if entry then
      out.entries[link.TraitNodeEntryID] = { definitionID = entry.TraitDefinitionID, type = entry.NodeEntryType, maxRanks = entry.MaxRanks }
      maxRanks = math.max(maxRanks, entry.MaxRanks or 0)
      local definition = definitionTable and definitionTable[entry.TraitDefinitionID]
      if definition then
        out.definitions[entry.TraitDefinitionID] =
          { spellID = definition.SpellID, overrideName = definition.OverrideName_lang, overrideIcon = definition.OverrideIcon }
        out.spellIDs[#out.spellIDs + 1] = definition.SpellID
      end
    end
  end
  return ids, maxRanks
end

-- { trees, nodes, entries, definitions } for trait tree treeID, or nil without an extract or a node of the tree. Ranks are
-- the server's: no node carries ranksPurchased (B7 defaults them to 0). Spells the definitions name are copied into
-- w.mock.spells.
function M.traits(w, treeID)
  local rows = BlizzardData.rowsBy(w, "TraitNode", "TraitTreeID", treeID)
  if #rows == 0 then
    return nil
  end
  local out = { trees = { [treeID] = { nodes = {} } }, nodes = {}, entries = {}, definitions = {}, spellIDs = {} }
  for _, row in ipairs(rows) do
    local nodes = out.trees[treeID].nodes
    nodes[#nodes + 1] = row.ID
    local entryIDs, maxRanks = entriesOf(w, row.ID, out)
    local edges = {}
    for _, edge in ipairs(BlizzardData.rowsBy(w, "TraitEdge", "LeftTraitNodeID", row.ID)) do
      edges[#edges + 1] = { targetNode = edge.RightTraitNodeID, type = edge.Type, visualStyle = edge.VisualStyle, isActive = false }
    end
    out.nodes[row.ID] =
      { posX = row.PosX, posY = row.PosY, type = row.Type, flags = row.Flags, entryIDs = entryIDs, maxRanks = maxRanks, visibleEdges = edges }
  end
  BlizzardData.spells(w, out.spellIDs)
  out.spellIDs = nil
  return out
end

return M
