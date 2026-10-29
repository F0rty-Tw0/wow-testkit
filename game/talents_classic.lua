-- Classic-family talent trees (B4, B5), read from w.mock.talents at call time: { unspent, groups, activeGroup, tabs = {
-- { id?, name, description?, icon, background, isUnlocked = true, talents = { { talentID?, name, icon, tier, column, rank = 0,
-- maxRank, meetsPrereq = true, previewRank = rank, meetsPreviewPrereq = meetsPrereq, isExceptional = false, hasGoldBorder =
-- false, prereqs = { { tier, column, isLearnable = true } } } } } }, grid = { [tier] = { [column] = { talentID, name, icon,
-- spellID, selected = false, available = true } } } }. tabs is the tbc and vanilla shape, grid the mists one. The names
-- install on vanilla, tbc and mists only, so the retail spec system stays as it is even where its data has the name.
local M = {}

local Requests = require("game.requests")
local State = require("game.state")
local define = State.define
local unpack = unpack

M.FLAVORS = { "vanilla", "tbc", "mists" }
M.DEFAULTS = { talents = { unspent = 0, groups = 1, activeGroup = 1, tabs = {}, grid = {} } }

function M.isClassic(w)
  for _, flavor in ipairs(M.FLAVORS) do
    if flavor == w.flavor then
      return true
    end
  end
  return false
end

-- Installs name on the classic family only; the data decides nothing here (the retail data has some of these names).
function M.defineClassic(w, name, impl)
  return M.isClassic(w) and define(w, name, impl, M.FLAVORS)
end

-- value unless it is nil.
local function orDefault(value, fallback)
  if value == nil then
    return fallback
  end
  return value
end

-- source: assumed (B4) the defaults the row leaves open: meetsPrereq true, the preview mirrors the rank and the prereq,
-- no exceptional or gold-border flag. A TalentInfoResult (B5) from a store talent.
function M.result(talent)
  local rank = talent.rank or 0
  local meetsPrereq = talent.meetsPrereq ~= false
  return {
    talentID = talent.talentID,
    name = talent.name,
    icon = talent.icon,
    tier = talent.tier,
    column = talent.column,
    rank = rank,
    maxRank = talent.maxRank,
    meetsPrereq = meetsPrereq,
    previewRank = orDefault(talent.previewRank, rank),
    meetsPreviewPrereq = orDefault(talent.meetsPreviewPrereq, meetsPrereq),
    isExceptional = talent.isExceptional == true,
    hasGoldBorder = talent.hasGoldBorder == true,
    selected = rank > 0,
    known = rank > 0,
    available = meetsPrereq,
    spellID = talent.spellID,
  }
end

-- source: assumed (B5) a grid talent is one rank: rank 1 when selected, maxRank 1, meetsPrereq = available.
function M.gridResult(entry, tier, column)
  return M.result({
    talentID = entry.talentID,
    name = entry.name,
    icon = entry.icon,
    tier = tier,
    column = column,
    rank = entry.selected and 1 or 0,
    maxRank = 1,
    meetsPrereq = entry.available ~= false,
    spellID = entry.spellID,
  })
end

function M.tab(w, index)
  return w.mock.talents.tabs[index]
end

function M.talent(w, tabIndex, talentIndex)
  local tab = M.tab(w, tabIndex)
  return tab and tab.talents and tab.talents[talentIndex]
end

function M.pointsSpent(tab)
  local sum = 0
  for _, talent in ipairs(tab.talents or {}) do
    sum = sum + (talent.rank or 0)
  end
  return sum
end

local function isPlayer(unit)
  return type(unit) == "string" and unit:lower() == "player"
end

local function installTree(w)
  local function def(name, impl)
    M.defineClassic(w, name, impl)
  end
  -- source: confirmed (B4) the counts; assumed that mists counts its specializations in tabs.
  def("GetNumTalentTabs", function()
    return #w.mock.talents.tabs
  end)
  def("GetNumTalents", function(tab)
    local record = M.tab(w, tab)
    return record and #(record.talents or {}) or 0
  end)
  -- source: confirmed (B4) tier, column, isLearnable per prerequisite; assumed isLearnable true unless the prereq says no.
  def("GetTalentPrereqs", function(tab, index)
    local talent = M.talent(w, tab, index)
    local out = {}
    for _, prereq in ipairs(talent and talent.prereqs or {}) do
      out[#out + 1], out[#out + 2], out[#out + 3] = prereq.tier, prereq.column, prereq.isLearnable ~= false
    end
    return unpack(out)
  end)
  -- source: confirmed (talentframebase.lua:302) the window subtracts it from the unspent points; assumed it sums every tab's
  -- previewRank, whatever the pet and group arguments.
  def("GetGroupPreviewTalentPointsSpent", function()
    local sum = 0
    for _, tab in ipairs(w.mock.talents.tabs) do
      for _, talent in ipairs(tab.talents or {}) do
        sum = sum + M.result(talent).previewRank
      end
    end
    return sum
  end)
  def("GetUnspentTalentPoints", function()
    return w.mock.talents.unspent
  end)
  def("GetNumTalentGroups", function()
    return w.mock.talents.groups
  end)
  def("UnitCharacterPoints", function(unit)
    if isPlayer(unit) then
      return w.mock.talents.unspent
    end
  end)
end

local function installGridAndRequests(w)
  -- source: assumed (B5) tierAvailable true and unlock level 0; selectedColumn is 0 when the tier has no selected talent.
  M.defineClassic(w, "GetTalentTierInfo", function(tier)
    local selected = 0
    for column, entry in pairs(w.mock.talents.grid[tier] or {}) do
      if entry.selected then
        selected = column
      end
    end
    return true, selected, 0
  end)
  -- source: assumed (B13) the client only asks; the server answers with new ranks and an event.
  M.defineClassic(w, "LearnTalent", function(...)
    Requests.record(w, "LearnTalent", ...)
  end)
end

-- source: assumed (B4) the column count the classic window loops: four columns in the trees, three in the mists grid. The
-- generated API data holds 0 for it.
local COLUMNS = { vanilla = 4, tbc = 4, mists = 3 }

function M.install(w)
  if COLUMNS[w.flavor] then
    define(w, "Constants.TalentConsts.NumTalentColumns", COLUMNS[w.flavor], M.FLAVORS)
  end
  installTree(w)
  installGridAndRequests(w)
end

return M
