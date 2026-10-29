-- C_ClassTalents and C_Traits over w.mock.traits (B6, B7, B13): configs, tree nodes, node, entry and definition info and
-- the currency list, all read at call time.
local A = require("assert")
local G = require("tests.helpers.game")
local H = require("tests.helpers.world")

local TRAITS = {
  configID = 7,
  configs = { [7] = { name = "Kit Build", type = 1, treeIDs = { 790 }, usesSharedActionBars = false } },
  trees = { [790] = { nodes = { 101, 102 }, currencies = { { traitCurrencyID = 1, quantity = 3, maxQuantity = 31, spent = 2 } } } },
  nodes = {
    [101] = {
      posX = 600,
      posY = 1200,
      entryIDs = { 201 },
      ranksPurchased = 1,
      maxRanks = 1,
      visibleEdges = { { targetNode = 102, type = 1, visualStyle = 1, isActive = false } },
    },
    [102] = { entryIDs = { 202 }, maxRanks = 2 },
  },
  entries = { [201] = { definitionID = 301, maxRanks = 1 }, [202] = { definitionID = 302, maxRanks = 2 } },
  definitions = { [301] = { spellID = 9001 }, [302] = { spellID = 9002 } },
}

local function test_active_config_and_tree_nodes() -- (B6)
  G.withGame("retail", function(w)
    w:setMock({ traits = TRAITS })
    A.eq(_G.C_ClassTalents.GetActiveConfigID(), 7)
    A.same(_G.C_Traits.GetConfigInfo(7), { ID = 7, name = "Kit Build", type = 1, treeIDs = { 790 }, usesSharedActionBars = false })
    A.same(_G.C_Traits.GetTreeNodes(790), { 101, 102 })
  end)
end

local function test_node_info_defaults_ranks_and_availability_assumed() -- (B7)
  G.withGame("retail", function(w)
    w:setMock({ traits = TRAITS })
    local a, b = _G.C_Traits.GetNodeInfo(7, 101), _G.C_Traits.GetNodeInfo(7, 102)
    A.same(
      { a.ID, a.posX, a.ranksPurchased, a.activeRank, a.currentRank, a.isAvailable, a.isVisible, a.meetsEdgeRequirements },
      { 101, 600, 1, 1, 1, true, true, true }
    )
    A.same({ b.activeRank, b.maxRanks, #a.visibleEdges, a.visibleEdges[1].targetNode }, { 0, 2, 1, 102 })
  end)
end

local function test_node_info_is_a_fresh_table_per_call() -- (Blizzard code mutates what GetNodeInfo returns)
  G.withGame("retail", function(w)
    w:setMock({ traits = TRAITS })
    local a = _G.C_Traits.GetNodeInfo(7, 101)
    a.ranksPurchased = 99
    A.eq(_G.C_Traits.GetNodeInfo(7, 101).ranksPurchased, 1)
  end)
end

local function test_unknown_node_has_id_zero_assumed() -- (B6)
  G.withGame("retail", function(w)
    w:setMock({ traits = TRAITS })
    A.eq(_G.C_Traits.GetNodeInfo(7, 999).ID, 0)
  end)
end

local function test_entry_definition_and_currency() -- (B6)
  G.withGame("retail", function(w)
    w:setMock({ traits = TRAITS })
    A.same({ _G.C_Traits.GetEntryInfo(7, 202).definitionID, _G.C_Traits.GetDefinitionInfo(302).spellID }, { 302, 9002 })
    A.same(_G.C_Traits.GetTreeCurrencyInfo(7, 790, false), { { traitCurrencyID = 1, quantity = 3, maxQuantity = 31, spent = 2 } })
  end)
end

local function test_purchase_rank_records_and_keeps_ranks_assumed() -- (B13)
  G.withGame("retail", function(w)
    w:setMock({ traits = TRAITS })
    A.eq(_G.C_Traits.PurchaseRank(7, 102), true)
    A.same({ w.mock.requests[1].api, _G.C_Traits.GetNodeInfo(7, 102).ranksPurchased }, { "C_Traits.PurchaseRank", 0 })
  end)
end

local function test_class_talents_only_where_the_data_has_them()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists" }) do
    G.withGame(flavor, function()
      A.eq(H.lookup("C_ClassTalents.GetActiveConfigID"), nil, flavor)
    end)
  end
end

return function()
  test_active_config_and_tree_nodes()
  test_node_info_defaults_ranks_and_availability_assumed()
  test_node_info_is_a_fresh_table_per_call()
  test_unknown_node_has_id_zero_assumed()
  test_entry_definition_and_currency()
  test_purchase_rank_records_and_keeps_ranks_assumed()
  test_class_talents_only_where_the_data_has_them()
end
