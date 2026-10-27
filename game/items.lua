-- Item facts, money and the player's specialization, read from w.mock at call time. items = { [id] = { name, link,
-- quality, itemLevel, minLevel, type, subType, stackCount, equipLoc, icon, sellPrice, classID, subClassID, count } },
-- money in copper, spec = the current specialization index (false clears it) and specs = { [index] = { id, name,
-- description, icon, role, primaryStat } }. A known id with an absent field returns nothing for that value; an unknown
-- id returns the API's default and counts as unscripted.
local M = {}

local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

local unpack = unpack

M.DEFAULTS = { items = {}, money = 0, specs = {} }

-- source: assumed (row G13) the client's quality colours; no page lists them (the extract sets them in the engine).
local QUALITY_COLORS = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff", "00ccff" }

-- source: assumed (row G13) an item with no link field gets the client's link shape with no suffix or bonus data.
local function itemLink(id, record)
  if record.link ~= nil or record.name == nil then
    return record.link
  end
  local color = QUALITY_COLORS[record.quality] or QUALITY_COLORS[1]
  return string.format("|cff%s|Hitem:%d::::::::::::|h[%s]|h|r", color, id, record.name)
end

-- An item is named by id, by an "item:<id>" link or string, or by its name.
local function itemIdent(ident)
  if type(ident) == "string" then
    return tonumber(ident:match("item:(%d+)")) or ident
  end
  return ident
end

-- source: confirmed (row G13) C_Item.GetItemInfo returns nothing for an uncached or unknown item; the return order is
-- the wiki's (name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, icon, sellPrice, classID,
-- subClassID, bindType, expansionID, setID, isCraftingReagent, description).
local INFO_FIELDS = {
  "name",
  "link",
  "quality",
  "itemLevel",
  "minLevel",
  "type",
  "subType",
  "stackCount",
  "equipLoc",
  "icon",
  "sellPrice",
  "classID",
  "subClassID",
  "bindType",
  "expansionID",
  "setID",
  "isCraftingReagent",
  "description",
}

-- source: confirmed (row G13) itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID.
local INSTANT_FIELDS = { "type", "subType", "equipLoc", "icon", "classID", "subClassID" }

local function fieldList(id, record, fields)
  local out = {}
  for i, key in ipairs(fields) do
    out[i] = key == "link" and itemLink(id, record) or record[key]
  end
  return out
end

local function installItems(w)
  local function find(ident, name)
    local id, record = State.findRecord(w.mock.items, itemIdent(ident))
    if not id then
      WorldApi.markUnscripted(w, name)
    end
    return id, record
  end
  define(w, "C_Item.GetItemInfo", function(ident)
    local id, record = find(ident, "C_Item.GetItemInfo")
    if id then
      return unpack(fieldList(id, record, INFO_FIELDS), 1, #INFO_FIELDS)
    end
  end)
  define(w, "C_Item.GetItemInfoInstant", function(ident)
    local id, record = find(ident, "C_Item.GetItemInfoInstant")
    if id then
      return id, unpack(fieldList(id, record, INSTANT_FIELDS), 1, #INSTANT_FIELDS)
    end
  end)
  -- source: assumed (row G13) an item the mock does not hold counts 0; the client's count includes bags the mock does
  -- not model, so count is the whole answer whatever the include flags say.
  define(w, "C_Item.GetItemCount", function(ident)
    local id, record = find(ident, "C_Item.GetItemCount")
    return id and record.count or 0
  end)
  define(w, "C_Item.GetItemIconByID", function(ident)
    local id, record = find(ident, "C_Item.GetItemIconByID")
    if id then
      return record.icon
    end
  end)
end

local SPEC_FIELDS = { "id", "name", "description", "icon", "role", "primaryStat", "pointsSpent", "background", "previewPointsSpent", "isUnlocked" }

-- source: confirmed (row G13) nil without a specialization; the deprecation fallbacks of row G1 forward to the
-- C_SpecializationInfo names on retail and forever.
local function installSpecialization(w)
  local function specialization()
    return type(w.mock.spec) == "number" and w.mock.spec or nil
  end
  local function specializationInfo(index)
    local record = type(index) == "number" and w.mock.specs[index]
    if not record then
      WorldApi.markUnscripted(w, "C_SpecializationInfo.GetSpecializationInfo")
      return
    end
    return unpack(fieldList(index, record, SPEC_FIELDS), 1, #SPEC_FIELDS)
  end
  define(w, "C_SpecializationInfo.GetSpecialization", specialization)
  define(w, "C_SpecializationInfo.GetSpecializationInfo", specializationInfo)
  define(w, "GetSpecialization", specialization, { "retail", "forever" })
  define(w, "GetSpecializationInfo", specializationInfo, { "retail", "forever" })
end

function M.install(w)
  installItems(w)
  installSpecialization(w)
  -- source: confirmed (row G13) copper.
  define(w, "GetMoney", function()
    return w.mock.money
  end)
end

return M
