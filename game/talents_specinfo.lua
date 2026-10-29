-- C_SpecializationInfo on the classic family and the two deprecation wrappers Blizzard builds over it, all over the
-- w.mock.talents store of game/talents_classic.lua (B4, B5). The retail spec system (Task 7.3) is not touched.
local M = {}

local Classic = require("game.talents_classic")
local define = require("game.state").define

local NUM_COLUMNS = 3

M.DEFAULTS = {}

-- The TalentInfoResult a TalentInfoQuery names, or nil. A query with specializationIndex and talentIndex reads that tab's
-- talent; one with tier and column reads the grid first (mists, B5), then, with specializationIndex, that tab's talent at
-- the tier and column (assumed: the tbc and vanilla windows were not read).
local function findTalent(w, query)
  if type(query) ~= "table" then
    return nil
  end
  local tab, index = query.specializationIndex, query.talentIndex
  if tab and index then
    local talent = Classic.talent(w, tab, index)
    return talent and Classic.result(talent)
  end
  local tier, column = query.tier, query.column
  local entry = tier and column and (w.mock.talents.grid[tier] or {})[column]
  if entry then
    return Classic.gridResult(entry, tier, column)
  end
  for _, talent in ipairs(tab and tier and column and Classic.tab(w, tab) and Classic.tab(w, tab).talents or {}) do
    if talent.tier == tier and talent.column == column then
      return Classic.result(talent)
    end
  end
  return nil
end

local function installSpecialization(w)
  local def = function(name, impl)
    Classic.defineClassic(w, name, impl)
  end
  -- source: confirmed (B4) the return list; assumed previewPointsSpent = pointsSpent, isUnlocked true, no role or primaryStat.
  def("C_SpecializationInfo.GetSpecializationInfo", function(index)
    local tab = Classic.tab(w, index)
    if not tab then
      return nil
    end
    local spent = Classic.pointsSpent(tab)
    local preview = tab.previewPointsSpent
    if preview == nil then
      preview = spent
    end
    return tab.id or index, tab.name, tab.description, tab.icon, nil, nil, spent, tab.background, preview, tab.isUnlocked ~= false
  end)
  def("C_SpecializationInfo.GetTalentInfo", function(query)
    return findTalent(w, query)
  end)
  -- source: assumed (B4) the active group and that the talent UI is usable (ToggleTalentFrame checks it).
  def("C_SpecializationInfo.GetActiveSpecGroup", function()
    return w.mock.talents.activeGroup
  end)
  def("C_SpecializationInfo.CanPlayerUseTalentUI", function()
    return true
  end)
end

-- The 12 values both fallbacks return from a TalentInfoResult.
local function talentValues(info)
  return info.name,
    info.icon,
    info.tier,
    info.column,
    info.rank,
    info.maxRank,
    info.meetsPrereq,
    info.previewRank,
    info.meetsPreviewPrereq,
    info.isExceptional,
    info.hasGoldBorder,
    info.talentID
end

-- source: confirmed (B4) deprecated_specialization_tbc.lua (identical to _vanilla.lua): the query names the tab and the
-- talent index; the tab info drops role and primaryStat.
local function tbcWrappers(w)
  Classic.defineClassic(w, "GetTalentTabInfo", function(index, ...)
    local id, name, description, icon, _, _, spent, background, preview, unlocked = _G.C_SpecializationInfo.GetSpecializationInfo(index, ...)
    return id, name, description, icon, spent, background, preview, unlocked
  end)
  Classic.defineClassic(w, "GetTalentInfo", function(tab, index, isInspect, isPet, groupIndex)
    local info = _G.C_SpecializationInfo.GetTalentInfo({
      specializationIndex = tab,
      talentIndex = index,
      isInspect = isInspect,
      isPet = isPet,
      groupIndex = groupIndex,
    })
    if info then
      return talentValues(info)
    end
  end)
end

-- source: confirmed (B4) deprecated_specialization_mists.lua: the tab info keeps its first four values, the talent index
-- becomes tier ceil(index / 3) and column index % 3 (the fallback's own arithmetic, kept as the client has it).
local function mistsWrappers(w)
  Classic.defineClassic(w, "GetTalentTabInfo", function(index, ...)
    local id, name, description, icon = _G.C_SpecializationInfo.GetSpecializationInfo(index, ...)
    return id, name, description, icon
  end)
  Classic.defineClassic(w, "GetTalentInfo", function(_, index, isInspect, _, groupIndex)
    local info = _G.C_SpecializationInfo.GetTalentInfo({
      tier = math.ceil(index / NUM_COLUMNS),
      column = index % NUM_COLUMNS,
      groupIndex = groupIndex,
      isInspect = isInspect,
    })
    if info then
      return talentValues(info)
    end
  end)
end

-- source: assumed (B4) the kit's player may use the talent and specialization UIs; the names are in the retail and forever
-- API data.
local function installRetail(w)
  local function yes()
    return true
  end
  define(w, "C_SpecializationInfo.CanPlayerUseTalentUI", yes)
  define(w, "C_SpecializationInfo.CanPlayerUseTalentSpecUI", yes)
end

function M.install(w)
  installRetail(w)
  installSpecialization(w)
  if w.flavor == "mists" then
    mistsWrappers(w)
  else
    tbcWrappers(w)
  end
end

return M
