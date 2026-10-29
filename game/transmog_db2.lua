-- Transmog sources built from the client extract's DB2 tables (B17): ItemModifiedAppearance names the sources of an item and
-- ItemAppearance the item's default icon. The builder returns a table for BlizzardData.fill, so scenario data wins and no
-- extract means nil. The collected flags are the server's (B16), so a DB2 source is never collected.
local M = {}

local BlizzardData = require("blizzard_data")

-- Sets the icon of each item the store lacks one for (an item record the store lacks is created with just the icon).
local function fillIcon(w, itemID, iconFileID)
  local record = w.mock.items[itemID] or {}
  record.icon = record.icon or iconFileID
  w.mock.items[itemID] = record
end

-- { sourceInfo = { [sourceID] = { sourceID, visualID, itemID, itemModID } }, sources = { [visualID] = { sourceID, ... } } }
-- for itemIDs, one source per ItemModifiedAppearance row (the row ID is the source ID, in ascending order); nil without an
-- extract or the table. Copies each item's ItemAppearance default icon into w.mock.items when the store has none.
function M.sources(w, itemIDs)
  local appearances = BlizzardData.table(w, "ItemAppearance")
  if not BlizzardData.table(w, "ItemModifiedAppearance") then
    return nil
  end
  local out = { sourceInfo = {}, sources = {} }
  for _, itemID in ipairs(itemIDs) do
    for _, row in ipairs(BlizzardData.rowsBy(w, "ItemModifiedAppearance", "ItemID", itemID)) do
      local visualID = row.ItemAppearanceID
      out.sourceInfo[row.ID] = { sourceID = row.ID, visualID = visualID, itemID = itemID, itemModID = row.ItemAppearanceModifierID }
      out.sources[visualID] = out.sources[visualID] or {}
      table.insert(out.sources[visualID], row.ID)
      local icon = appearances and appearances[visualID] and appearances[visualID].DefaultIconFileDataID
      if icon then
        fillIcon(w, itemID, icon)
      end
    end
  end
  return out
end

return M
