-- Unit fixtures: w:unit / w:mouseover and the kit implementations of the Unit* answers.
local A = require("assert")
local H = require("tests.helpers.world")
local Units = require("units")

local lookup = H.lookup
local MYTHIC_SUMMARY = "C_PlayerInfo.GetPlayerMythicPlusRatingSummary"
local MYTHIC_SCORE = 2500

local function withUnits(flavor, fn)
  H.withWorld(flavor, function(w)
    Units.install(w)
    fn(w)
  end)
end

local function test_mouseover_aliases_registered_unit()
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob", guid = "G1" })
    w:mouseover("target")
    A.eq(_G.UnitIsUnit("mouseover", "target"), true)
    A.eq(_G.UnitTokenFromGUID("G1"), "target")
    A.eq(_G.UnitExists("mouseover"), true)
    A.eq(_G.UnitExists("party1"), false)
  end)
end

local function test_unit_name_returns_name_and_realm()
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob" })
    local name, realm = _G.UnitName("target")
    A.eq(name, "Bob")
    A.eq(realm, nil)
    w:unit("target", { name = "Bob", realm = "R" })
    A.same({ _G.UnitName("target") }, { "Bob", "R" })
  end)
end

local function test_mythic_score_only_where_api_exists()
  withUnits("vanilla", function(w)
    w:unit("player", { mythicScore = MYTHIC_SCORE })
    A.eq(lookup(MYTHIC_SUMMARY), nil)
  end)
  withUnits("retail", function(w)
    w:unit("player", { mythicScore = MYTHIC_SCORE })
    A.eq(lookup(MYTHIC_SUMMARY)("player").currentSeasonScore, MYTHIC_SCORE)
  end)
end

local function test_addon_context_still_validates()
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob" })
    A.errors(function()
      w:run("addon", _G.UnitName, nil)
    end, "UnitName")
  end)
end

local function test_stub_wins_over_fixture()
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob" })
    w:stub("UnitName", { returns = { "Stubbed" } })
    A.eq(_G.UnitName("target"), "Stubbed")
  end)
end

local function test_player_fixture_gets_player_guid()
  withUnits("retail", function(w)
    w:unit("target", { isPlayer = true })
    w:unit("focus", {})
    A.eq(_G.UnitGUID("target"):sub(1, 7), "Player-")
    A.eq(_G.UnitGUID("focus"):sub(1, 9), "Creature-")
  end)
end

local function test_unset_unit_returns_manifest_defaults()
  withUnits("retail", function()
    A.same({ _G.UnitName("target") }, { "", "" })
    A.eq(_G.UnitHealth("target"), 0)
    A.eq(_G.UnitGUID("target"), nil)
  end)
end

local function test_unset_field_returns_manifest_default()
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob" })
    A.eq(_G.UnitLevel("target"), 0)
    A.eq(_G.UnitIsPlayer("target"), false)
  end)
end

local function test_fixture_fields_answer_their_apis()
  withUnits("retail", function(w)
    w:unit("target", { classFile = "MAGE", className = "Mage", level = 80, health = 5, healthMax = 9, guild = "G", guildRank = "Officer" })
    A.same({ _G.UnitClass("target") }, { "Mage", "MAGE" })
    A.eq(_G.UnitLevel("target"), 80)
    A.same({ _G.UnitHealth("target"), _G.UnitHealthMax("target") }, { 5, 9 })
    A.same({ _G.GetGuildInfo("target") }, { "G", "Officer", 0 })
  end)
end

local function test_race_and_faction_shapes()
  withUnits("vanilla", function(w)
    w:unit("target", { raceName = "Night Elf", raceFile = "NightElf", faction = "Alliance" })
    A.same({ _G.UnitRace("target") }, { "Night Elf", "NightElf" })
    A.same({ _G.UnitFactionGroup("target") }, { "Alliance", "Alliance" })
  end)
end

local function test_removing_unit_and_clearing_mouseover()
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob" })
    w:mouseover("target")
    w:mouseover(nil)
    A.eq(_G.UnitExists("mouseover"), false)
    w:unit("target", nil)
    A.eq(_G.UnitExists("target"), false)
  end)
end

-- wiki API_UnitTokenFromGUID: "Unit tokens will be tested in the order given below, returning the first one that
-- matches": player, vehicle, pet, party<x>, partypet<x>, raid<x>, raidpet<x>, nameplate<x>, arena<x>, arenapet<x>,
-- boss<x>, target, focus, npc, mouseover, softenemy, softfriend, softinteract.
local function test_token_from_guid_follows_the_wiki_order()
  withUnits("retail", function(w)
    w:unit("target", { guid = "G1" })
    w:unit("focus", { guid = "G1" })
    w:mouseover("target")
    A.eq(_G.UnitTokenFromGUID("G1"), "target")
    w:unit("party2", { guid = "G1" })
    w:unit("party10", { guid = "G1" })
    A.eq(_G.UnitTokenFromGUID("G1"), "party2")
    w:unit("player", { guid = "G1" })
    A.eq(_G.UnitTokenFromGUID("G1"), "player")
    A.eq(_G.UnitTokenFromGUID("G2"), nil)
    w:unit("arena1", { guid = "G3" })
    w:unit("nameplate100", { guid = "G3" })
    A.eq(_G.UnitTokenFromGUID("G3"), "nameplate100")
  end)
end

-- "mouseover" is in the wiki's list, so it answers through the w:mouseover alias even when the aliased token is not.
local function test_token_from_guid_answers_mouseover_aliasing_an_unlisted_token()
  withUnits("retail", function(w)
    w:unit("targettarget", { guid = "G1" })
    w:mouseover("targettarget")
    A.eq(_G.UnitTokenFromGUID("G1"), "mouseover")
  end)
end

-- Unit indexes start at 1 with no leading zero (wiki UnitToken: "partyN", N "1,2,3 or 4"), so party0 and party01 are
-- not tested.
local function test_token_from_guid_skips_index_zero_and_leading_zeros()
  withUnits("retail", function(w)
    w:unit("party0", { guid = "G1" })
    w:unit("party01", { guid = "G1" })
    A.eq(_G.UnitTokenFromGUID("G1"), nil)
  end)
end

-- A token outside the wiki's list (targettarget) is never tested.
local function test_token_from_guid_skips_unlisted_tokens()
  withUnits("retail", function(w)
    w:unit("targettarget", { guid = "G1" })
    A.eq(_G.UnitTokenFromGUID("G1"), nil)
  end)
end

-- wiki API_UnitTokenFromGUID tests "mouseover" 15th of 18, after every other token the kit's fixtures name.
local function test_token_from_guid_falls_back_to_mouseover()
  withUnits("retail", function(w)
    w:unit("mouseover", { guid = "G1" })
    A.eq(_G.UnitTokenFromGUID("G1"), "mouseover")
  end)
end

local function test_missing_fixture_counts_as_unscripted()
  withUnits("retail", function(w)
    _G.UnitName("party1")
    A.eq(w.unscripted.UnitName, 1)
  end)
end

local function test_fixture_answer_not_counted_as_unscripted()
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob" })
    _G.UnitName("target")
    A.eq(w.unscripted.UnitName, nil)
  end)
end

local function test_unset_field_counts_as_unscripted()
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob" })
    _G.UnitLevel("target")
    A.eq(w.unscripted.UnitLevel, 1)
  end)
end

local function test_tokens_are_case_insensitive()
  withUnits("retail", function(w)
    w:unit("Target", { name = "Bob" })
    w:mouseover("TARGET")
    A.eq(_G.UnitName("TARGET"), "Bob")
    A.eq(_G.UnitName("MouseOver"), "Bob")
  end)
end

local function test_effective_level_falls_back_to_level()
  withUnits("retail", function(w)
    w:unit("target", { level = 70 })
    A.eq(_G.UnitEffectiveLevel("target"), 70)
    w:unit("target", { level = 70, effectiveLevel = 60 })
    A.eq(_G.UnitEffectiveLevel("target"), 60)
  end)
end

local function test_pvp_field_answers_unit_is_pvp()
  withUnits("retail", function(w)
    w:unit("target", { pvp = true })
    A.eq(_G.UnitIsPVP("target"), true)
  end)
end

return function()
  test_mouseover_aliases_registered_unit()
  test_unit_name_returns_name_and_realm()
  test_mythic_score_only_where_api_exists()
  test_addon_context_still_validates()
  test_stub_wins_over_fixture()
  test_player_fixture_gets_player_guid()
  test_unset_unit_returns_manifest_defaults()
  test_unset_field_returns_manifest_default()
  test_fixture_fields_answer_their_apis()
  test_race_and_faction_shapes()
  test_removing_unit_and_clearing_mouseover()
  test_token_from_guid_follows_the_wiki_order()
  test_token_from_guid_skips_unlisted_tokens()
  test_token_from_guid_answers_mouseover_aliasing_an_unlisted_token()
  test_token_from_guid_skips_index_zero_and_leading_zeros()
  test_token_from_guid_falls_back_to_mouseover()
  test_missing_fixture_counts_as_unscripted()
  test_fixture_answer_not_counted_as_unscripted()
  test_unset_field_counts_as_unscripted()
  test_tokens_are_case_insensitive()
  test_effective_level_falls_back_to_level()
  test_pvp_field_answers_unit_is_pvp()
end
