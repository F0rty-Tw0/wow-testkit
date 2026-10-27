-- Spell info, texture, link, cooldown and known, all read from w.mock.spells.
local A = require("assert")
local Flavors = require("tools.flavors")
local G = require("tests.helpers.game")

local FIREBALL = { [133] = { name = "Fireball", icon = 135812, castTime = 3500, minRange = 0, maxRange = 40 } }
local COOLDOWN = { start = 10, duration = 8, enabled = true }

local function test_legacy_spell_info_on_classic_flavors() -- (G1, G13)
  for _, flavor in ipairs({ "vanilla", "tbc", "mists" }) do
    G.withGame(flavor, function(w)
      w:setMock({ spells = FIREBALL })
      A.same({ _G.GetSpellInfo(133) }, { "Fireball", nil, 135812, 3500, 0, 40, 133, 135812 }, flavor)
      A.eq(_G.GetSpellTexture(133), 135812, flavor)
    end)
  end
end

local function test_legacy_spell_names_absent_where_the_data_lacks_them() -- (G1)
  for _, flavor in ipairs({ "retail", "forever" }) do
    G.withGame(flavor, function()
      for _, name in ipairs({ "GetSpellInfo", "GetSpellTexture", "GetSpellLink", "GetSpellCooldown" }) do
        A.eq(rawget(_G, name), nil, flavor .. " " .. name)
      end
    end)
  end
end

local function test_c_spell_info_is_a_table_found_by_id_or_name() -- (G13)
  G.withGame("retail", function(w)
    w:setMock({ spells = FIREBALL })
    local info = _G.C_Spell.GetSpellInfo(133)
    A.same({ info.name, info.iconID, info.originalIconID, info.spellID, info.castTime }, { "Fireball", 135812, 135812, 133, 3500 })
    A.eq(_G.C_Spell.GetSpellInfo("Fireball").spellID, 133)
  end)
end

local function test_unknown_spell_counts_unscripted() -- (G13)
  G.withGame("retail", function(w)
    A.eq(_G.C_Spell.GetSpellInfo(999), nil)
    A.eq(w.unscripted["C_Spell.GetSpellInfo"], 1)
    A.eq(_G.C_Spell.GetSpellInfo("No Such Spell"), nil)
    A.eq(w.unscripted["C_Spell.GetSpellInfo"], 2)
  end)
end

local function test_absent_field_on_a_known_spell_is_scripted() -- (G13)
  G.withGame("retail", function(w)
    w:setMock({ spells = { [133] = { name = "Fireball" } } })
    local info = _G.C_Spell.GetSpellInfo(133)
    A.same({ info.name, info.iconID, info.castTime }, { "Fireball" })
    A.eq(w.unscripted["C_Spell.GetSpellInfo"], nil)
  end)
end

local function test_spell_link_format_assumed() -- (G13)
  G.withGame("retail", function(w)
    w:setMock({ spells = FIREBALL })
    A.eq(_G.C_Spell.GetSpellLink(133), "|cff71d5ff|Hspell:133:0|h[Fireball]|h|r")
  end)
  G.withGame("vanilla", function(w)
    w:setMock({ spells = FIREBALL })
    A.eq(_G.GetSpellLink(133), "|cff71d5ff|Hspell:133:0|h[Fireball]|h|r")
  end)
end

local function test_texture_cooldown_and_known() -- (G13)
  G.withGame("retail", function(w)
    w:setMock({ spells = FIREBALL })
    w:setMock({ spells = { [133] = { cooldown = COOLDOWN } } })
    A.eq(_G.C_Spell.GetSpellTexture(133), 135812)
    local cd = _G.C_Spell.GetSpellCooldown(133)
    A.same({ cd.startTime, cd.duration, cd.isEnabled, cd.modRate }, { 10, 8, true, 1 })
  end)
  G.withGame("vanilla", function(w)
    w:setMock({ spells = { [133] = { name = "Fireball", cooldown = COOLDOWN } } })
    A.same({ _G.GetSpellCooldown(133) }, { 10, 8, 1, 1 })
    w:setMock({ spells = { [133] = { cooldown = { enabled = false } } } })
    A.eq(select(3, _G.GetSpellCooldown(133)), 0)
  end)
end

local function test_spell_without_cooldown_data_is_ready_assumed() -- (G13)
  G.withGame("vanilla", function(w)
    w:setMock({ spells = FIREBALL })
    A.same({ _G.GetSpellCooldown(133) }, { 0, 0, 1, 1 })
    A.same({ _G.GetSpellCooldown(999) }, {})
    A.eq(w.unscripted["GetSpellCooldown"], 1)
  end)
end

local function test_is_spell_known_on_every_flavor_assumed() -- (G1, G13)
  for _, flavor in ipairs(Flavors.list) do
    G.withGame(flavor, function(w)
      w:setMock({ spells = { [133] = { name = "Fireball" }, [134] = { name = "Gone", known = false } } })
      A.same({ _G.IsSpellKnown(133), _G.IsSpellKnown(134), _G.IsSpellKnown(999) }, { true, false, false }, flavor)
      A.eq(w.unscripted["IsSpellKnown"], 1, flavor)
    end)
  end
end

return function()
  test_legacy_spell_info_on_classic_flavors()
  test_legacy_spell_names_absent_where_the_data_lacks_them()
  test_c_spell_info_is_a_table_found_by_id_or_name()
  test_unknown_spell_counts_unscripted()
  test_absent_field_on_a_known_spell_is_scripted()
  test_spell_link_format_assumed()
  test_texture_cooldown_and_known()
  test_spell_without_cooldown_data_is_ready_assumed()
  test_is_spell_known_on_every_flavor_assumed()
end
