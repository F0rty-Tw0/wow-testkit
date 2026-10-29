-- The classic-family talent trees (B4, B5, B13): tree counts, talent info, tab info, prereqs, points, the mists grid and
-- the learn request, all read from w.mock.talents at call time.
local A = require("assert")
local G = require("tests.helpers.game")
local H = require("tests.helpers.world")

-- Every field of the B4 return list is set, so the order test below does not lean on a default.
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
        {
          talentID = 11,
          name = "Kit Strike",
          icon = 132292,
          tier = 1,
          column = 2,
          rank = 2,
          maxRank = 5,
          meetsPrereq = true,
          previewRank = 2,
          meetsPreviewPrereq = true,
          isExceptional = false,
          hasGoldBorder = false,
        },
        {
          talentID = 12,
          name = "Kit Rage",
          icon = 132275,
          tier = 2,
          column = 2,
          rank = 0,
          maxRank = 1,
          meetsPrereq = true,
          previewRank = 0,
          meetsPreviewPrereq = true,
          isExceptional = true,
          hasGoldBorder = false,
          prereqs = { { tier = 1, column = 2 } },
        },
      },
    },
  },
}

local function test_tree_counts_and_prereqs() -- (B4)
  G.withGame("vanilla", function(w)
    w:setMock({ talents = TABS })
    A.same({ _G.GetNumTalentTabs(), _G.GetNumTalents(1), _G.UnitCharacterPoints("player") }, { 1, 2, 3 })
    A.same({ _G.GetTalentPrereqs(1, 2) }, { 1, 2, true })
  end)
end

local function test_talent_info_return_order() -- (B4: name, icon, tier, column, rank, maxRank, meetsPrereq, previewRank, meetsPreviewPrereq, isExceptional, hasGoldBorder, talentID)
  for _, flavor in ipairs({ "vanilla", "tbc" }) do
    G.withGame(flavor, function(w)
      w:setMock({ talents = TABS })
      A.same({ _G.GetTalentInfo(1, 2) }, { "Kit Rage", 132275, 2, 2, 0, 1, true, 0, true, true, false, 12 }, flavor)
      A.eq(_G.GetTalentInfo(1, 99), nil, flavor)
    end)
  end
end

local function test_talent_info_defaults_assumed() -- (B4: the row names the fields, not their defaults)
  G.withGame("tbc", function(w)
    w:setMock({ talents = { tabs = { { name = "T", talents = { { name = "Kit Bare", tier = 1, column = 1, rank = 3, maxRank = 5 } } } } } })
    local _, _, _, _, rank, _, meetsPrereq, previewRank, meetsPreviewPrereq, isExceptional, hasGoldBorder = _G.GetTalentInfo(1, 1)
    A.same({ rank, meetsPrereq, previewRank, meetsPreviewPrereq, isExceptional, hasGoldBorder }, { 3, true, 3, true, false, false })
  end)
end

local function test_tab_info_return_order_and_points_spent() -- (B4: id, name, description, icon, pointsSpent, background, previewPointsSpent, isUnlocked)
  for _, flavor in ipairs({ "vanilla", "tbc" }) do
    G.withGame(flavor, function(w)
      w:setMock({ talents = TABS })
      local id, name, description, icon, pointsSpent, background = _G.GetTalentTabInfo(1)
      A.same({ id, name, description, icon, pointsSpent, background }, { 161, "Kit Arms", "Kit tree", 132292, 2, "KitArms" }, flavor) -- pointsSpent = 2 + 0
    end)
  end
end

local function test_tab_preview_points_and_unlocked_default_assumed() -- (B4)
  G.withGame("tbc", function(w)
    w:setMock({ talents = TABS })
    local _, _, _, _, _, _, previewPointsSpent, isUnlocked = _G.GetTalentTabInfo(1)
    A.same({ previewPointsSpent, isUnlocked }, { 2, true })
  end)
end

local function test_tree_api_absent_on_retail_and_forever() -- (B4: the tree names are in the mists, vanilla and tbc data only)
  for _, flavor in ipairs({ "retail", "forever" }) do
    G.withGame(flavor, function()
      A.same({ H.lookup("GetNumTalentTabs"), H.lookup("GetTalentTabInfo"), H.lookup("GetTalentInfo") }, {}, flavor)
    end)
  end
end

local function test_mists_grid_answers_talent_info_queries() -- (B5)
  G.withGame("mists", function(w)
    w:setMock({ talents = { grid = { [1] = { [3] = { talentID = 19, name = "Kit Leap", icon = 132331, spellID = 9003, selected = true } } } } })
    local r = _G.C_SpecializationInfo.GetTalentInfo({ tier = 1, column = 3, groupIndex = 1 })
    A.same({ r.talentID, r.name, r.tier, r.column, r.selected, r.available, r.spellID }, { 19, "Kit Leap", 1, 3, true, true, 9003 })
    A.eq(_G.C_SpecializationInfo.GetTalentInfo({ tier = 2, column = 1 }), nil)
  end)
end

local function test_learn_talent_records_and_changes_nothing_assumed() -- (B13)
  G.withGame("vanilla", function(w)
    w:setMock({ talents = TABS })
    _G.LearnTalent(1, 2)
    A.same({ w.mock.requests[1].api, (select(5, _G.GetTalentInfo(1, 2))) }, { "LearnTalent", 0 })
  end)
end

local function test_group_preview_points_sum_every_tab_assumed() -- (B4: TalentFrame_UpdateTalentPoints subtracts it from the unspent points)
  G.withGame("tbc", function(w)
    w:setMock({ talents = TABS })
    A.eq(_G.GetGroupPreviewTalentPointsSpent(false, 1), 2) -- Kit Strike previewRank 2 + Kit Rage 0
  end)
end

local function test_column_count_constant_answers_per_flavor_assumed() -- the generated API data holds 0; TalentFrame_Load loops it
  for flavor, columns in pairs({ vanilla = 4, tbc = 4, mists = 3 }) do
    G.withGame(flavor, function()
      A.eq(_G.Constants.TalentConsts.NumTalentColumns, columns, flavor)
    end)
  end
end

return function()
  test_column_count_constant_answers_per_flavor_assumed()
  test_tree_counts_and_prereqs()
  test_talent_info_return_order()
  test_talent_info_defaults_assumed()
  test_tab_info_return_order_and_points_spent()
  test_tab_preview_points_and_unlocked_default_assumed()
  test_tree_api_absent_on_retail_and_forever()
  test_mists_grid_answers_talent_info_queries()
  test_learn_talent_records_and_changes_nothing_assumed()
  test_group_preview_points_sum_every_tab_assumed()
end
