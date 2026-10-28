-- C_SpecializationInfo on the classic family and the two deprecation wrappers built over it (B4, B5): the window-facing
-- names read the same w.mock.talents store as the plain readers.
local A = require("assert")
local G = require("tests.helpers.game")
local H = require("tests.helpers.world")

local TABS = {
  unspent = 3,
  tabs = {
    {
      id = 161,
      name = "Kit Arms",
      description = "Kit tree",
      icon = 132292,
      background = "KitArms",
      talents = {
        { talentID = 11, name = "Kit Strike", icon = 132292, tier = 1, column = 2, rank = 2, maxRank = 5 },
        {
          talentID = 12,
          name = "Kit Rage",
          icon = 132275,
          tier = 2,
          column = 2,
          rank = 0,
          maxRank = 1,
          isExceptional = true,
          prereqs = { { tier = 1, column = 2 } },
        },
      },
    },
  },
}

local function test_legacy_wrappers_return_the_specialization_readers_fields() -- (B4: the fallback's own composition)
  for _, flavor in ipairs({ "vanilla", "tbc" }) do
    G.withGame(flavor, function(w)
      w:setMock({ talents = TABS })
      local id, name, description, icon, _, _, spent, background, preview, unlocked = _G.C_SpecializationInfo.GetSpecializationInfo(1)
      A.same({ _G.GetTalentTabInfo(1) }, { id, name, description, icon, spent, background, preview, unlocked }, flavor)
      local r = _G.C_SpecializationInfo.GetTalentInfo({ specializationIndex = 1, talentIndex = 2 })
      A.same({ r.name, r.tier, r.column, r.rank, r.maxRank, r.talentID, r.selected }, { "Kit Rage", 2, 2, 0, 1, 12, false }, flavor)
    end)
  end
end

local function test_talent_info_query_by_tier_and_column_in_a_tab_assumed() -- (B4/B5; the tbc window's query shape was not read)
  G.withGame("tbc", function(w)
    w:setMock({ talents = TABS })
    A.eq(_G.C_SpecializationInfo.GetTalentInfo({ specializationIndex = 1, tier = 2, column = 2 }).name, "Kit Rage")
    A.eq(_G.C_SpecializationInfo.GetTalentInfo({ specializationIndex = 1, tier = 3, column = 1 }), nil)
  end)
end

local function test_mists_legacy_names_follow_the_55_fallback_shape() -- (B4: deprecated_specialization_mists.lua)
  G.withGame("mists", function(w)
    w:setMock({
      talents = {
        tabs = { { id = 62, name = "Kit Spec", description = "Kit spec text", icon = 132292 } },
        grid = { [2] = { [1] = { talentID = 21, name = "Kit Dash", icon = 132331, spellID = 9004 } } },
      },
    })
    A.same({ select("#", _G.GetTalentTabInfo(1)), _G.GetTalentTabInfo(1) }, { 4, 62, "Kit Spec", "Kit spec text", 132292 })
    -- talentIndex 4 -> tier ceil(4 / 3) = 2, column 4 % 3 = 1: the fallback's own arithmetic, kept as the client has it
    A.same({ _G.GetTalentInfo(1, 4) }, { "Kit Dash", 132331, 2, 1, 0, 1, true, 0, true, false, false, 21 })
  end)
end

local function test_talent_window_support_calls_assumed() -- (B4/B5: the calls the mists window makes; tbc and vanilla assumed alike)
  for _, flavor in ipairs({ "vanilla", "tbc", "mists" }) do
    G.withGame(flavor, function(w)
      w:setMock({ talents = TABS })
      A.same({
        _G.GetNumTalentTabs(false, false),
        _G.GetUnspentTalentPoints(false, false, 1),
        _G.GetNumTalentGroups(false, false),
        _G.C_SpecializationInfo.GetActiveSpecGroup(),
        _G.C_SpecializationInfo.CanPlayerUseTalentUI(),
      }, { 1, 3, 1, 1, true }, flavor)
    end)
  end
end

local function test_tier_info_reads_the_grid_assumed() -- (B5)
  G.withGame("mists", function(w)
    w:setMock({ talents = { grid = { [1] = { [3] = { talentID = 19, name = "Kit Leap", icon = 132331, spellID = 9003, selected = true } } } } })
    A.same({ _G.GetTalentTierInfo(1, 1, false, "player") }, { true, 3, 0 }) -- tierAvailable, selectedColumn; unlock level default 0
    A.eq(select(2, _G.GetTalentTierInfo(2, 1, false, "player")), 0)
  end)
end

local function test_retail_specialization_info_is_not_replaced() -- (B4: the retail spec system is Task 7.3's)
  G.withGame("retail", function(w)
    w:setMock({ talents = TABS })
    A.same({ _G.C_SpecializationInfo.GetSpecializationInfo(1) }, {})
    A.eq(H.lookup("GetTalentTabInfo"), nil)
    A.eq(w.unscripted["C_SpecializationInfo.GetSpecializationInfo"], 1)
  end)
end

return function()
  test_legacy_wrappers_return_the_specialization_readers_fields()
  test_talent_info_query_by_tier_and_column_in_a_tab_assumed()
  test_mists_legacy_names_follow_the_55_fallback_shape()
  test_talent_window_support_calls_assumed()
  test_tier_info_reads_the_grid_assumed()
  test_retail_specialization_info_is_not_replaced()
end
