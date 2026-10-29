-- The transmog APIs, read from w.mock.transmog at call time: atNPC, categories = { [category] = { name, isWeapon,
-- canHaveIllusions, canMainHand, canOffHand, canRanged } }, appearances = { [category] = { TransmogCategoryAppearanceInfo } },
-- sources = { [visualID] = { sourceID } }, sourceInfo = { [sourceID] = { visualID, itemID, itemModID = 0, categoryID,
-- isCollected = false, ... } }, items = { itemID } (the ids the DB2 fill expands), outfits = { TransmogOutfitEntryInfo },
-- activeOutfitID, viewedOutfitID?, slotGroups = { { position, appearanceSlotInfo = { TransmogOutfitSlotInfo },
-- illusionSlotInfo = { TransmogOutfitSlotInfo } } }, slots = { ["<slot>:<type>:<option>"] = ViewedTransmogOutfitSlotInfo }.
-- The collected flags are the server's,
-- so only the scenario sets them (B16); the kit never owns, favorites or applies anything. CommitAndApplyAllPending only
-- records a request (B13). Every other C_TransmogOutfitInfo name stays on the permissive stub.
local M = {}

local Requests = require("game.requests")
local State = require("game.state")
local define = State.define

local ENGINE = "blizzard"

M.DEFAULTS = {
  transmog = {
    atNPC = false,
    categories = {},
    appearances = {},
    sources = {},
    sourceInfo = {},
    items = {},
    outfits = {},
    slotGroups = {},
    slots = {},
  },
}

local function boolDefault(value, default)
  if value == nil then
    return default
  end
  return value
end

-- source: confirmed (B16, api/retail/TransmogItems.lua:1926) the fields; assumed absent booleans are false except
-- canDisplayOnPlayer and isUsable (true), and an absent number is 0.
local function appearanceOf(record)
  return {
    visualID = record.visualID,
    isCollected = record.isCollected == true,
    isFavorite = record.isFavorite == true,
    isHideVisual = record.isHideVisual == true,
    canDisplayOnPlayer = boolDefault(record.canDisplayOnPlayer, true),
    uiOrder = record.uiOrder or 0,
    exclusions = record.exclusions or 0,
    isUsable = boolDefault(record.isUsable, true),
    hasRequiredHoliday = record.hasRequiredHoliday == true,
    hasActiveRequiredHoliday = record.hasActiveRequiredHoliday == true,
    alwaysShowItem = record.alwaysShowItem,
  }
end

-- source: confirmed (B16, api/retail/AppearanceSource.lua) the fields; assumed itemModID 0, isCollected false, invType 0 and
-- the three can-flags true (the kit has no player to disqualify), and the item store's name and quality when the record has
-- none.
local function sourceOf(w, sourceID)
  local record = w.mock.transmog.sourceInfo[sourceID]
  if not record then
    return
  end
  local item = w.mock.items[record.itemID] or {}
  return {
    visualID = record.visualID,
    sourceID = sourceID,
    isCollected = record.isCollected == true,
    itemID = record.itemID,
    itemModID = record.itemModID or 0,
    invType = record.invType or 0,
    categoryID = record.categoryID,
    playerCanCollect = boolDefault(record.playerCanCollect, true),
    isValidSourceForPlayer = boolDefault(record.isValidSourceForPlayer, true),
    canDisplayOnPlayer = boolDefault(record.canDisplayOnPlayer, true),
    name = record.name or item.name,
    quality = record.quality or item.quality,
  }
end

local function installCollection(w)
  local function appearances(category)
    return w.mock.transmog.appearances[category] or {}
  end

  define(w, "C_TransmogCollection.GetCategoryInfo", function(category)
    local info = w.mock.transmog.categories[category]
    if info then
      return info.name,
        info.isWeapon == true,
        info.canHaveIllusions == true,
        info.canMainHand == true,
        info.canOffHand == true,
        info.canRanged == true
    end
  end)
  -- source: assumed (B16) transmogLocation is accepted and ignored: the argument is documented, no filtering rule is.
  define(w, "C_TransmogCollection.GetCategoryAppearances", function(category)
    local out = {}
    for i, record in ipairs(appearances(category)) do
      out[i] = appearanceOf(record)
    end
    return out
  end)
  -- source: assumed the count is the collected appearances of the category and the total all of them.
  define(w, "C_TransmogCollection.GetCategoryCollectedCount", function(category)
    local count = 0
    for _, record in ipairs(appearances(category)) do
      count = count + (record.isCollected and 1 or 0)
    end
    return count
  end)
  define(w, "C_TransmogCollection.GetCategoryTotal", function(category)
    return #appearances(category)
  end)
  define(w, "C_TransmogCollection.GetAllAppearanceSources", function(visualID)
    local out = {}
    for i, sourceID in ipairs(w.mock.transmog.sources[visualID] or {}) do
      out[i] = sourceID
    end
    return out
  end)
  define(w, "C_TransmogCollection.GetAppearanceSources", function(visualID)
    local out = {}
    for _, sourceID in ipairs(w.mock.transmog.sources[visualID] or {}) do
      out[#out + 1] = sourceOf(w, sourceID)
    end
    return out
  end)
  define(w, "C_TransmogCollection.GetSourceInfo", function(sourceID)
    return sourceOf(w, sourceID)
  end)
  -- source: assumed the player has the transmog when a collected source names the item and modifier (default 0).
  define(w, "C_TransmogCollection.PlayerHasTransmog", function(itemID, modID)
    for _, record in pairs(w.mock.transmog.sourceInfo) do
      if record.itemID == itemID and (record.itemModID or 0) == (modID or 0) and record.isCollected then
        return true
      end
    end
    return false
  end)
end

local function installOutfits(w)
  define(w, "C_Transmog.IsAtTransmogNPC", function()
    return w.mock.transmog.atNPC == true
  end)
  define(w, "C_Transmog.GetItemIDForSource", function(sourceID)
    local record = w.mock.transmog.sourceInfo[sourceID]
    return record and record.itemID
  end)
  -- source: confirmed (B16, api/retail/TransmogOutfitInfo.lua:1335) the fields; assumed situationCategories {}, isEventOutfit
  -- and isDisabled false, and playerFacingOutfitIndex the list position.
  define(w, "C_TransmogOutfitInfo.GetOutfitsInfo", function()
    local out = {}
    for i, record in ipairs(w.mock.transmog.outfits) do
      out[i] = {
        outfitID = record.outfitID,
        name = record.name,
        situationCategories = record.situationCategories or {},
        icon = record.icon,
        isEventOutfit = record.isEventOutfit == true,
        isDisabled = record.isDisabled == true,
        playerFacingOutfitIndex = record.playerFacingOutfitIndex or i,
      }
    end
    return out
  end)
  define(w, "C_TransmogOutfitInfo.GetActiveOutfitID", function()
    return w.mock.transmog.activeOutfitID
  end)
  -- source: assumed the viewed outfit is the scenario's viewedOutfitID, else the active one.
  define(w, "C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID", function()
    return w.mock.transmog.viewedOutfitID or w.mock.transmog.activeOutfitID
  end)
  -- source: assumed the client answers on its next frame with VIEWED_TRANSMOG_OUTFIT_CHANGED, on which the window builds its
  -- slots: the window calls this from its OnShow, before the frames inside it have run theirs and registered for the event.
  define(w, "C_TransmogOutfitInfo.ChangeViewedOutfit", function(outfitID)
    w.mock.transmog.viewedOutfitID = outfitID
    w:schedule(0, function()
      w:run(ENGINE, w.fire, w, "VIEWED_TRANSMOG_OUTFIT_CHANGED")
    end, 1)
  end)
  -- source: confirmed (B16, api/retail/TransmogOutfitInfo.lua) the shapes (TransmogOutfitSlotGroup, TransmogOutfitSlotInfo);
  -- assumed the layout is the scenario's, since no installed file says which slot sits in which group.
  define(w, "C_TransmogOutfitInfo.GetSlotGroupInfo", function()
    return w.mock.transmog.slotGroups
  end)
  -- The appearance slots of every group in order, then the illusion slots of every group.
  define(w, "C_TransmogOutfitInfo.GetAllSlotLocationInfo", function()
    local appearance, illusion = {}, {}
    for _, group in ipairs(w.mock.transmog.slotGroups) do
      for _, info in ipairs(group.appearanceSlotInfo or {}) do
        appearance[#appearance + 1] = info
      end
      for _, info in ipairs(group.illusionSlotInfo or {}) do
        illusion[#illusion + 1] = info
      end
    end
    return appearance, illusion
  end)
  -- The scenario's record for slotKey "<slot>:<type>:<option>", as set.
  define(w, "C_TransmogOutfitInfo.GetViewedOutfitSlotInfo", function(slot, kind, option)
    return w.mock.transmog.slots[tostring(slot) .. ":" .. tostring(kind) .. ":" .. tostring(option)]
  end)
  define(w, "C_TransmogOutfitInfo.CommitAndApplyAllPending", function(...)
    Requests.record(w, "C_TransmogOutfitInfo.CommitAndApplyAllPending", ...)
  end)
end

function M.install(w)
  installCollection(w)
  installOutfits(w)
end

return M
