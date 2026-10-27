-- Combat spell facts: scenario data first, then the client extract's SpellName table, then a placeholder.
local A = require("assert")
local H = require("tests.helpers.combat")
local HC = require("tests.helpers.client")
local Spells = require("combat_spells")
local Tmp = require("tests.helpers.tmp")

local function test_spell_info_prefers_scenario_data_then_fallback()
  H.withCombat("retail", function(w)
    local info = Spells.info(w, H.SPELLS.STRIKE)
    A.same({ info.name, info.school, info.spellID }, { "Kit Strike", 1, H.SPELLS.STRIKE })
    A.eq(Spells.info(w, 424242).name, "Spell 424242")
    A.eq(_G.C_Spell.GetSpellInfo(H.SPELLS.BOLT).castTime, 2000)
    A.eq(w.combat.spells, w.mock.spells)
  end)
end

local function test_spell_name_falls_back_to_the_extract()
  H.withCombat("retail", function(w)
    local root = Tmp.dir("combat-db2")
    w.client = HC.extract(root, "retail", "1", { ["db2/spellname.lua"] = "return { [777] = { Name_lang = 'Kit Name' } }" })
    A.eq(Spells.extractName(w, 777), "Kit Name")
    A.eq(Spells.info(w, 777).name, "Kit Name")
    A.eq(_G.C_Spell.GetSpellInfo(777).name, "Kit Name") -- Task 7.4's reader asks the extract for an id it lacks
    A.eq(Spells.extractName(w, 778), nil)
    A.eq(Spells.info(w, 778).name, "Spell 778")
  end)
end

local function test_spell_name_without_an_extract_is_nil()
  H.withCombat("retail", function(w)
    A.eq(Spells.extractName(w, 777), nil)
  end)
end

return function()
  test_spell_info_prefers_scenario_data_then_fallback()
  test_spell_name_falls_back_to_the_extract()
  test_spell_name_without_an_extract_is_nil()
end
