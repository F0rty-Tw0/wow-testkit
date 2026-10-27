-- Extra unit answers: fixture fields, names, cast and channel tuples, and the legacy aura tuples.
local A = require("assert")
local G = require("tests.helpers.game")
local H = require("tests.helpers.world")
local Units = require("units")

local function withUnits(flavor, fn)
  H.withWorld(flavor, function(w)
    Units.install(w)
    fn(w)
  end)
end

local function test_simple_fields_answer_from_the_fixture()
  withUnits("retail", function(w)
    w:unit("target", {
      classFile = "MAGE",
      sex = 3,
      powerType = 0,
      powerToken = "MANA",
      isDead = true,
      isGhost = false,
      isAFK = true,
      isDND = false,
      classification = "elite",
      creatureType = "Humanoid",
      threat = 2,
      absorbs = 50,
      incomingHeals = 120,
    })
    A.same({ _G.UnitClassBase("target"), _G.UnitSex("target"), _G.UnitIsDead("target"), _G.UnitIsAFK("target") }, { "MAGE", 3, true, true })
    A.same({ _G.UnitPowerType("target") }, { 0, "MANA" })
    A.same({ _G.UnitClassification("target"), _G.UnitCreatureType("target"), _G.UnitThreatSituation("target") }, { "elite", "Humanoid", 2 })
    A.same({ _G.UnitGetTotalAbsorbs("target"), _G.UnitGetIncomingHeals("target") }, { 50, 120 })
  end)
end

local function test_threat_situation_reads_the_status_against_one_mob() -- (C12)
  withUnits("retail", function(w)
    w:unit("boss1", { guid = "Creature-0-0-0-0-77" })
    w:unit("party1", { threat = 1, threatOn = { ["Creature-0-0-0-0-77"] = 3 } })
    A.same({ _G.UnitThreatSituation("party1"), _G.UnitThreatSituation("party1", "boss1") }, { 1, 3 })
    w:unit("party2", { threatOn = {} })
    A.eq(_G.UnitThreatSituation("party2", "boss1"), nil)
    A.eq(w.unscripted.UnitThreatSituation, nil)
    A.eq(_G.UnitThreatSituation("party1", "boss9"), nil)
  end)
end

local function test_dead_or_ghost()
  withUnits("retail", function(w)
    w:unit("target", { isDead = false, isGhost = true })
    A.same({ _G.UnitIsDeadOrGhost("target"), _G.UnitIsDead("target") }, { true, false })
    w:unit("focus", {})
    A.eq(_G.UnitIsDeadOrGhost("focus"), false)
    A.eq(w.unscripted.UnitIsDeadOrGhost, nil)
    A.eq(_G.UnitIsDeadOrGhost("party3"), false)
    A.eq(w.unscripted.UnitIsDeadOrGhost, 1)
  end)
end

local function test_connected_and_visible_default_true_assumed() -- (G11)
  withUnits("retail", function(w)
    w:unit("target", {})
    A.same({ _G.UnitIsConnected("target"), _G.UnitIsVisible("target") }, { true, true })
    A.eq(w.unscripted.UnitIsConnected, nil)
    w:unit("focus", { isConnected = false })
    A.eq(_G.UnitIsConnected("focus"), false)
    A.eq(_G.UnitIsConnected("party3"), false)
    A.eq(w.unscripted.UnitIsConnected, 1)
  end)
end

local function test_enemy_and_attackable_are_read_for_the_player_only_assumed() -- (G11)
  withUnits("retail", function(w)
    w:unit("target", { isEnemy = true, canAttack = true })
    A.same({ _G.UnitIsEnemy("player", "target"), _G.UnitCanAttack("player", "target") }, { true, true })
    A.eq(_G.UnitIsEnemy("target", "player"), false)
    A.eq(w.unscripted.UnitIsEnemy, 1)
  end)
end

local function test_full_and_display_names() -- (G10)
  withUnits("retail", function(w)
    w:unit("target", { name = "Bob", realm = "Ravenholdt" })
    A.same({ _G.UnitFullName("target") }, { "Bob", "Ravenholdt" })
    A.eq(_G.GetUnitName("target", true), "Bob-Ravenholdt")
    w:unit("party1", { name = "Amy" })
    A.same({ _G.UnitFullName("party1") }, { "Amy" })
    A.eq(_G.GetUnitName("party1", true), "Amy")
    A.eq(_G.GetUnitName("party1"), "Amy")
  end)
end

local function test_foreign_realm_label_and_player_realm_assumed() -- (G10)
  G.withGame("retail", function(w)
    w:unit("target", { name = "Bob", realm = "Ravenholdt" })
    A.eq(_G.GetUnitName("target"), "Bob" .. (_G.FOREIGN_SERVER_LABEL or " (*)"))
    w:setMock({ realm = "Kirin Tor" })
    w:unit("player", { name = "Viewer" })
    A.same({ _G.UnitFullName("player") }, { "Viewer", "KirinTor" })
  end)
end

local function test_unknown_unit_names_are_unscripted() -- (G10)
  withUnits("retail", function(w)
    A.eq((_G.UnitFullName("party3")), "")
    A.eq(w.unscripted.UnitFullName, 1)
    A.eq(_G.GetUnitName("party3"), nil)
    A.eq(w.unscripted.GetUnitName, 1)
  end)
end

local function test_cast_and_channel_tuples_assumed() -- (G12)
  withUnits("retail", function(w)
    w:unit("target", {
      cast = {
        name = "Fireball",
        displayName = "Fireball",
        textureID = 135812,
        startTimeMs = 1000,
        endTimeMs = 3500,
        isTradeskill = false,
        castID = "C1",
        notInterruptible = false,
        castingSpellID = 133,
      },
    })
    A.same({ _G.UnitCastingInfo("target") }, { "Fireball", "Fireball", 135812, 1000, 3500, false, "C1", false, 133 })
    A.same({ _G.UnitChannelInfo("target") }, {})
    A.eq(w.unscripted.UnitChannelInfo, nil)
    w:unit("focus", {
      channel = {
        name = "Drain",
        displayName = "Drain",
        textureID = 136163,
        startTimeMs = 0,
        endTimeMs = 5000,
        isTradeskill = false,
        notInterruptible = true,
        spellID = 689,
      },
    })
    A.same({ _G.UnitChannelInfo("focus") }, { "Drain", "Drain", 136163, 0, 5000, false, true, 689 })
  end)
end

local function test_aura_tuples_on_classic_flavors_assumed() -- (G1, G12)
  withUnits("vanilla", function(w)
    w:unit("target", {
      auras = {
        {
          name = "Renew",
          icon = 135953,
          applications = 1,
          duration = 15,
          expirationTime = 130,
          sourceUnit = "player",
          spellId = 139,
          isHelpful = true,
        },
        {
          name = "Agony",
          icon = 136139,
          applications = 2,
          dispelName = "Curse",
          duration = 24,
          expirationTime = 140,
          sourceUnit = "player",
          spellId = 980,
          isHelpful = false,
        },
        { name = "Fortitude", icon = 135987, applications = 1, spellId = 21562, isHelpful = true, points = { 7, 9 } },
      },
    })
    A.same({ _G.UnitBuff("target", 1) }, { "Renew", 135953, 1, nil, 15, 130, "player", nil, nil, 139 })
    A.same({ _G.UnitDebuff("target", 1) }, { "Agony", 136139, 2, "Curse", 24, 140, "player", nil, nil, 980 })
    A.eq(_G.UnitAura("target", 1, "HARMFUL"), "Agony")
    A.eq(_G.UnitAura("target", 2, "HELPFUL"), "Fortitude")
    A.eq(_G.UnitAura("target", 2), "Fortitude")
    A.same({ _G.UnitAura("target", 2, "HELPFUL") }, { "Fortitude", 135987, 1, nil, nil, nil, nil, nil, nil, 21562, nil, nil, nil, nil, nil, 7, 9 })
    A.same({ _G.UnitBuff("target", 3) }, {})
    A.same({ _G.UnitBuff("nobody", 1) }, {})
    A.eq(w.unscripted.UnitBuff, 1)
  end)
end

local function test_aura_tuples_exist_only_on_the_classic_flavors() -- (G1)
  for flavor, expected in pairs({ retail = false, forever = false, mists = true, tbc = true, vanilla = true }) do
    withUnits(flavor, function()
      A.eq(H.lookup("UnitAura") ~= nil, expected)
      A.eq(H.lookup("UnitBuff") ~= nil, expected)
      A.eq(H.lookup("UnitDebuff") ~= nil, expected)
    end)
  end
end

return function()
  test_simple_fields_answer_from_the_fixture()
  test_threat_situation_reads_the_status_against_one_mob()
  test_dead_or_ghost()
  test_connected_and_visible_default_true_assumed()
  test_enemy_and_attackable_are_read_for_the_player_only_assumed()
  test_full_and_display_names()
  test_foreign_realm_label_and_player_realm_assumed()
  test_unknown_unit_names_are_unscripted()
  test_cast_and_channel_tuples_assumed()
  test_aura_tuples_on_classic_flavors_assumed()
  test_aura_tuples_exist_only_on_the_classic_flavors()
end
