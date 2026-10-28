-- Talent data built from the extract's DB2 tables (game/talents_db2.lua): the classic tabs of the player's class, the
-- trait tree nodes, entries, definitions and edges, and scenario data winning over both. Every table is kit-authored
-- (tests/helpers/windows.lua), never a Blizzard row.
local A = require("assert")
local BlizzardData = require("blizzard_data")
local TalentsDb2 = require("game.talents_db2")
local W = require("tests.helpers.windows")

local NINE = "{ %s, 0, 0, 0, 0, 0, 0, 0 }"
local DB2 = {
  talenttab = [[return {
    [3] = { ID = 3, Name_lang = "Kit Arms", Description_lang = "Kit tree", ClassMask = 1, OrderIndex = 0, BackgroundFile = "KitArms" },
    [4] = { ID = 4, Name_lang = "Kit Holy", ClassMask = 2, OrderIndex = 0, BackgroundFile = "KitHoly" },
  }]],
  talent = "return {"
    .. ("[5] = { ID = 5, TabID = 3, TierID = 0, ColumnIndex = 1, SpellRank = " .. NINE:format("9001, 9002") .. ", PrereqTalent = { 0, 0, 0 }, PrereqRank = { 0, 0, 0 } },")
    .. ("[6] = { ID = 6, TabID = 3, TierID = 1, ColumnIndex = 0, SpellRank = " .. NINE:format("9003") .. ", PrereqTalent = { 5, 0, 0 }, PrereqRank = { 1, 0, 0 } },")
    .. "}",
  spellname = "return { [9001] = { ID = 9001, Name_lang = 'Kit Strike' }, [9002] = { ID = 9002, Name_lang = 'Kit Strike' }, [9003] = { ID = 9003, Name_lang = 'Kit Rage' } }",
  spellmisc = "return { [9001] = { ID = 9001, SpellID = 9001, SpellIconFileDataID = 132292 }, [9003] = { ID = 9003, SpellID = 9003, SpellIconFileDataID = 132275 } }",
  traitnode = [[return {
    [101] = { ID = 101, TraitTreeID = 790, PosX = 600, PosY = 1200, Type = 0, Flags = 0 },
    [102] = { ID = 102, TraitTreeID = 790, PosX = 900, PosY = 1200, Type = 0, Flags = 0 },
    [103] = { ID = 103, TraitTreeID = 791, PosX = 0, PosY = 0, Type = 0, Flags = 0 },
  }]],
  traitnodextraitnodeentry = "return { [1] = { ID = 1, TraitNodeID = 101, TraitNodeEntryID = 201, Index = 0 }, [2] = { ID = 2, TraitNodeID = 102, TraitNodeEntryID = 202, Index = 0 } }",
  traitnodeentry = "return { [201] = { ID = 201, TraitDefinitionID = 301, NodeEntryType = 1, MaxRanks = 1 }, [202] = { ID = 202, TraitDefinitionID = 302, NodeEntryType = 1, MaxRanks = 2 } }",
  traitdefinition = "return { [301] = { ID = 301, SpellID = 9001 }, [302] = { ID = 302, SpellID = 9003 } }",
  traitedge = "return { [1] = { ID = 1, LeftTraitNodeID = 101, RightTraitNodeID = 102, Type = 1, VisualStyle = 0 } }",
}
local INDEX = {
  ["talent.tabid"] = "return { [3] = { 5, 6 }, [4] = {} }",
  ["traitnode.traittreeid"] = "return { [790] = { 101, 102 }, [791] = { 103 } }",
  ["traitnodextraitnodeentry.traitnodeid"] = "return { [101] = { 1 }, [102] = { 2 } }",
  ["traitedge.lefttraitnodeid"] = "return { [101] = { 1 } }",
}
local OPTS = { db2 = DB2, index = INDEX }
local PLAYER = { classFile = "WARRIOR", className = "Warrior", isPlayer = true }
local CONFIG = { configID = 7, configs = { [7] = { ID = 7, name = "Kit Build", type = 1, treeIDs = { 790 } } } }

local function test_classic_tabs_build_for_the_player_class_assumed() -- (B17: ClassMask bit 2^(classID - 1), tier/column are 0-based)
  W.withWindows("tbc", OPTS, function(w)
    w:unit("player", PLAYER)
    BlizzardData.fill(w, "talents", TalentsDb2.classic)
    A.same({ _G.GetNumTalentTabs(), _G.GetNumTalents(1) }, { 1, 2 }) -- the ClassMask = 2 tab is another class's
    A.same({ _G.GetTalentInfo(1, 1) }, { "Kit Strike", 132292, 1, 2, 0, 2, true, 0, true, false, false, 5 })
    local id, name, description, icon, _, background = _G.GetTalentTabInfo(1)
    A.same({ id, name, description, background }, { 3, "Kit Arms", "Kit tree", "KitArms" })
    A.eq(icon, nil) -- the tab icon is SpellIconID, a table this phase does not export
  end)
end

local function test_prereq_talent_ids_resolve_to_tier_and_column_assumed() -- (B17: PrereqTalent holds Talent row ids)
  W.withWindows("tbc", OPTS, function(w)
    w:unit("player", PLAYER)
    BlizzardData.fill(w, "talents", TalentsDb2.classic)
    A.same({ _G.GetTalentPrereqs(1, 2) }, { 1, 2, true })
    A.eq(w.mock.talents.tabs[1].talents[2].prereqs[1].rank, 1)
  end)
end

local function test_classic_without_a_player_class_or_extract_builds_nothing()
  W.withWindows("tbc", OPTS, function(w) -- no player fixture: no class
    A.eq(TalentsDb2.classic(w), nil)
  end)
  W.withWindows("tbc", {}, function(w)
    w:unit("player", PLAYER)
    A.same({ BlizzardData.fill(w, "talents", TalentsDb2.classic), #w.mock.talents.tabs }, { false, 0 })
  end)
end

local function test_trait_tree_builds_nodes_entries_and_edges()
  W.withWindows("retail", OPTS, function(w)
    w:setMock({ traits = CONFIG })
    BlizzardData.fill(w, "traits", function()
      return TalentsDb2.traits(w, 790)
    end)
    A.same(_G.C_Traits.GetTreeNodes(790), { 101, 102 }) -- node 103 belongs to tree 791
    local a, b = _G.C_Traits.GetNodeInfo(7, 101), _G.C_Traits.GetNodeInfo(7, 102)
    A.same({ a.posX, a.entryIDs, b.maxRanks, a.visibleEdges[1].targetNode }, { 600, { 201 }, 2, 102 })
    A.same({ _G.C_Traits.GetEntryInfo(7, 202).definitionID, _G.C_Traits.GetDefinitionInfo(302).spellID }, { 302, 9003 })
    A.eq(w.mock.spells[9003].name, "Kit Rage") -- definitions hydrate the spell store
  end)
end

local function test_scenario_ranks_override_db2_geometry()
  W.withWindows("retail", OPTS, function(w)
    w:setMock({ traits = CONFIG })
    w:setMock({ traits = { nodes = { [101] = { ID = 101, ranksPurchased = 1, posX = 5 } } } })
    BlizzardData.fill(w, "traits", function()
      return TalentsDb2.traits(w, 790)
    end)
    local a = _G.C_Traits.GetNodeInfo(7, 101)
    A.same({ a.ranksPurchased, a.posX, a.posY }, { 1, 5, 1200 }) -- scenario keys win, DB2 fills the rest
  end)
end

local function test_opener_builds_the_trait_tree_and_sets_ranks_after()
  W.scenario("retail", OPTS, function(s)
    s:openWindow("talents", { treeID = 790, ranks = { [101] = 1, [102] = 2 }, classFile = "ignored", unspent = 9 })
    local w = s.w
    A.same({ _G.C_ClassTalents.GetActiveConfigID(), _G.C_Traits.GetTreeNodes(790) }, { 1, { 101, 102 } })
    local a, b = _G.C_Traits.GetNodeInfo(1, 101), _G.C_Traits.GetNodeInfo(1, 102)
    A.same({ a.ranksPurchased, a.posX, b.ranksPurchased, w.mock.talents.unspent }, { 1, 600, 2, 0 }) -- the classic keys are ignored
  end)
end

local function test_opener_builds_classic_tabs_with_ranks_by_talent_id()
  W.scenario("tbc", OPTS, function(s)
    s:openWindow("talents", { classFile = "WARRIOR", unspent = 4, ranks = { [6] = 1 } })
    A.same({ _G.UnitCharacterPoints("player"), (select(5, _G.GetTalentInfo(1, 2))), (select(5, _G.GetTalentInfo(1, 1))) }, { 4, 1, 0 })
    A.eq(s.w.mock.traits.configID, nil) -- the trait keys are ignored
  end)
end

local function test_opener_uses_the_kit_stand_in_only_without_extract_data()
  local kit = { tabs = { { name = "Kit Tab", talents = { { name = "Kit Bolt", tier = 1, column = 1, maxRank = 1 } } } } }
  W.scenario("tbc", {}, function(s)
    s:openWindow("talents", { kit = kit })
    A.eq((_G.GetTalentInfo(1, 1)), "Kit Bolt")
  end)
  W.scenario("tbc", OPTS, function(s)
    s:openWindow("talents", { classFile = "WARRIOR", kit = kit })
    A.eq((_G.GetTalentInfo(1, 1)), "Kit Strike") -- the extract built the tab, so the stand-in is not applied
  end)
end

return function()
  test_classic_tabs_build_for_the_player_class_assumed()
  test_prereq_talent_ids_resolve_to_tier_and_column_assumed()
  test_classic_without_a_player_class_or_extract_builds_nothing()
  test_trait_tree_builds_nodes_entries_and_edges()
  test_scenario_ranks_override_db2_geometry()
  test_opener_builds_the_trait_tree_and_sets_ranks_after()
  test_opener_builds_classic_tabs_with_ranks_by_talent_id()
  test_opener_uses_the_kit_stand_in_only_without_extract_data()
end
