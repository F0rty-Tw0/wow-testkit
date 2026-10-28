-- Window data from the client extract's DB2 tables (Phase 12): builders read rows here, never at answer time. Scenario
-- data always wins: a fill merges key by key without overwriting, and no extract means no change.
local M = {}

local Client = require("client")
local CombatSpells = require("combat_spells")
local State = require("game.state")

-- The DB2 table name as the export wrote it ({ [id] = row }), or nil without an extract or a table.
function M.table(w, name)
  return Client.db2(w.client, name)
end

-- The rows of table name whose column equals value, ascending by row ID, through the export's index file; {} when the
-- extract, the index or the table is missing. Never scans.
function M.rowsBy(w, name, column, value)
  local ids = Client.db2Index(w.client, name, column)
  local rows, table = {}, M.table(w, name)
  for _, id in ipairs(ids and table and ids[value] or {}) do
    rows[#rows + 1] = table[id]
  end
  return rows
end

-- Merges build(w) into w.mock[key] without overwriting a key already set; true when something was merged. false
-- without an extract (build is not called) or when build returns no table.
function M.fill(w, key, build)
  if not w.client then
    return false
  end
  local built = build(w)
  if type(built) ~= "table" then
    return false
  end
  w.mock[key] = w.mock[key] or {}
  State.fill(w.mock[key], built)
  return true
end

-- Copies each id absent from w.mock.items from ItemSparse and Item into it (B17 names); an id in neither stays absent.
function M.items(w, ids)
  local sparse, item = M.table(w, "ItemSparse"), M.table(w, "Item")
  for _, id in ipairs(ids) do
    local s, i = sparse and sparse[id], item and item[id]
    if w.mock.items[id] == nil and (s or i) then
      s, i = s or {}, i or {}
      w.mock.items[id] = {
        name = s.Display_lang,
        quality = s.OverallQualityID,
        itemLevel = s.ItemLevel,
        stackCount = s.Stackable,
        icon = i.IconFileDataID,
        classID = i.ClassID,
        subClassID = i.SubclassID,
      }
    end
  end
end

-- { [classID] = { name, subClasses = { [subClassID] = name } } } from ItemClass and ItemSubClass, both walked whole (a
-- few hundred rows; rows are keyed by row ID, the API by ClassID and SubClassID), or nil without ItemClass.
-- source: assumed (row BU22) a subclass is named by VerboseName_lang ("One-Handed Axes"), by DisplayName_lang ("Axe") when
-- that is empty; no installed file shows which column the engine reads.
function M.itemClasses(w)
  local classes, subClasses = M.table(w, "ItemClass"), M.table(w, "ItemSubClass")
  if not classes then
    return nil
  end
  local out = {}
  for _, row in pairs(classes) do
    out[row.ClassID] = { name = row.ClassName_lang, subClasses = {} }
  end
  for _, row in pairs(subClasses or {}) do
    local class = out[row.ClassID]
    if class then
      local verbose = row.VerboseName_lang
      class.subClasses[row.SubClassID] = verbose ~= nil and verbose ~= "" and verbose or row.DisplayName_lang
    end
  end
  return out
end

-- Copies each id absent from w.mock.spells as { name, icon } from SpellName and SpellMisc (keyed by SpellID); an id in
-- neither stays absent.
function M.spells(w, ids)
  local misc = M.table(w, "SpellMisc")
  for _, id in ipairs(ids) do
    local name, row = CombatSpells.extractName(w, id), misc and misc[id]
    if w.mock.spells[id] == nil and (name or row) then
      w.mock.spells[id] = { name = name, icon = row and row.SpellIconFileDataID }
    end
  end
end

return M
