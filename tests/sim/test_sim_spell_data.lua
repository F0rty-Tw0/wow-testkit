-- SimSpellData: DB2 rows to the normalized spell record (units, array columns, unknown effects), the kit-literal
-- fallback and override, the cache, and the publish into w.mock.spells that never overwrites scenario data. Every
-- extract is a kit-authored mini one (tests/helpers/windows.lua); no real client is read.
local A = require("assert")
local SimSpellData = require("sim_spell_data")
local W = require("tests.helpers.windows")

local KIT = 900001

local DB2 = {
  spellname = "return { [900001] = { Name_lang = 'Kit Bolt' } }",
  spellmisc = "return { [900001] = { SpellID = 900001, SpellIconFileDataID = 132337, SchoolMask = 4, CastingTimeIndex = 7, DurationIndex = 3, RangeIndex = 5 } }",
  spellcasttimes = "return { [7] = { Base = 2500 } }",
  spellrange = "return { [5] = { RangeMin = {0, 3}, RangeMax = {40, 30} } }",
  spellduration = "return { [3] = { Duration = 8000 } }",
  spellcooldowns = "return { [1] = { SpellID = 900001, RecoveryTime = 10000, StartRecoveryTime = 1500 } }",
  spellpower = "return { [1] = { SpellID = 900001, PowerType = 0, ManaCost = 30 } }",
  spelleffect = "return { [11] = { SpellID = 900001, EffectIndex = 0, Effect = 2, EffectBasePoints = 19, ImplicitTarget = {6, 0} },"
    .. " [12] = { SpellID = 900001, EffectIndex = 1, Effect = 6, EffectAura = 26, ImplicitTarget = {6, 0} },"
    .. " [13] = { SpellID = 900001, EffectIndex = 2, Effect = 250, ImplicitTarget = {0, 0} } }",
}

-- db2/index/<name>.<column>.lua beside the chunked or small table (Client.db2Index reads either form).
local INDEX = {
  ["spelleffect.spellid"] = "return { [900001] = { 11, 12, 13 } }",
  ["spellcooldowns.spellid"] = "return { [900001] = { 1 } }",
  ["spellpower.spellid"] = "return { [900001] = { 1 } }",
}

local function withKit(flavor, db2, fn)
  W.withWindows(flavor, { db2 = db2, index = INDEX }, fn)
end

-- A copy of DB2 with the given tables replaced or added.
local function db2With(replace)
  local out = {}
  for name, source in pairs(DB2) do
    out[name] = source
  end
  for name, source in pairs(replace) do
    out[name] = source
  end

  return out
end

local function test_a_db2_spell_normalizes_units_and_fields_assumed()
  for _, flavor in ipairs({ "retail", "tbc" }) do
    withKit(flavor, DB2, function(w) -- no w.sim here: get must not need one
      A.same(SimSpellData.get(w, KIT), {
        id = KIT,
        name = "Kit Bolt",
        icon = 132337,
        school = 4,
        castTime = 2500,
        cooldown = 10000,
        gcd = 1500,
        duration = 8000,
        minRange = 0,
        maxRange = 40,
        cost = { type = "MANA", amount = 30 },
        ground = false,
        effects = { { type = "damage", base = 19, target = "enemy" }, { type = "aura", aura = "root", base = 0, target = "enemy" } },
      })
      A.eq(w.unscripted["sim:effect:250"], 1) -- an unknown effect is skipped and counted, not fatal
      A.eq(SimSpellData.get(w, 424242), nil) -- no SpellName row, no literal
    end)
  end
end

local function test_a_kit_literal_wins_for_effects_and_db2_for_numbers_assumed()
  withKit("retail", DB2, function(w)
    w.sim = {}
    w:setMock({ spells = { [KIT] = { name = "Scenario" } } })
    SimSpellData.put(w, { id = KIT, castTime = 1, effects = { { type = "damage", base = 7, target = "enemy" } } })
    SimSpellData.publish(w, KIT)
    A.same({ w.mock.spells[KIT].name, w.mock.spells[KIT].castTime, w.mock.spells[KIT].maxRange }, { "Scenario", 2500, 40 })
    A.same(w.mock.spells[KIT].icon, 132337)
    A.eq(SimSpellData.get(w, KIT).effects[1].base, 7)
    A.eq(SimSpellData.get(w, KIT).castTime, 2500)
  end)
end

-- source: assumed (user ruling 2026-11-10: tbc 70577 Blizzard costs 320 mana, past the sim's 100-point bar) a literal's cost
-- is on the sim's power scale and wins; a literal without one takes the extract's.
local function test_a_kit_literals_cost_wins_over_the_extracts()
  withKit("tbc", DB2, function(w)
    w.sim = {}
    SimSpellData.put(w, { id = KIT, cost = { type = "MANA", amount = 5 } })
    A.same(SimSpellData.get(w, KIT).cost, { type = "MANA", amount = 5 })
    SimSpellData.put(w, { id = KIT })
    A.same(SimSpellData.get(w, KIT).cost, { type = "MANA", amount = 30 })
  end)
end

local function test_get_caches_and_put_invalidates()
  withKit("retail", DB2, function(w)
    w.sim = {}
    local first = SimSpellData.get(w, KIT)
    A.eq(SimSpellData.get(w, KIT) == first, true)
    A.eq(w.sim.spellData[KIT], first)
    SimSpellData.put(w, { id = KIT, effects = {} })
    A.eq(#SimSpellData.get(w, KIT).effects, 0)
  end)
end

local function test_ground_and_radius_come_from_the_effect_row_assumed()
  local db2 = db2With({
    spelleffect = "return { [21] = { SpellID = 900001, EffectIndex = 0, Effect = 27, EffectAura = 3, EffectAuraPeriod = 1000,"
      .. " EffectBasePoints = 5, EffectRadiusIndex = {9, 0}, ImplicitTarget = {15, 0} } }",
    spellradius = "return { [9] = { Radius = 8 } }",
  })
  W.withWindows("retail", { db2 = db2, index = { ["spelleffect.spellid"] = "return { [900001] = { 21 } }" } }, function(w)
    local record = SimSpellData.get(w, KIT)
    A.eq(record.ground, true)
    A.same(record.effects, { { type = "persistent", aura = "periodic", base = 5, target = "areaDest", radius = 8, period = 1000 } })
  end)
end

local function test_effect_and_aura_and_target_numbers_assumed()
  A.same(
    { SimSpellData.EFFECT[2], SimSpellData.EFFECT[6], SimSpellData.EFFECT[17], SimSpellData.EFFECT[27] },
    { "damage", "aura", "damage", "persistent" }
  )
  A.same({ SimSpellData.EFFECT[30], SimSpellData.EFFECT[96], SimSpellData.EFFECT[64] }, { "energize", "charge", "trigger" })
  A.same({ SimSpellData.AURA[3], SimSpellData.AURA[12], SimSpellData.AURA[26] }, { "periodic", "stun", "root" })
  A.same(
    { SimSpellData.target(1), SimSpellData.target(6), SimSpellData.target(22), SimSpellData.target(16) },
    { "caster", "enemy", "areaSource", "areaSource" }
  )
  A.same({ SimSpellData.target(15), SimSpellData.target(18), SimSpellData.target(0), SimSpellData.target(nil) }, { "areaDest", "areaDest" })
end

local function test_an_unlisted_aura_is_dummy_and_a_trigger_names_its_spell_assumed()
  local db2 = db2With({
    spelleffect = "return { [31] = { SpellID = 900001, EffectIndex = 0, Effect = 6, EffectAura = 99, ImplicitTarget = {1, 0} },"
      .. " [32] = { SpellID = 900001, EffectIndex = 1, Effect = 64, EffectTriggerSpell = 900002, ImplicitTarget = {1, 0} } }",
  })
  W.withWindows("retail", { db2 = db2, index = { ["spelleffect.spellid"] = "return { [900001] = { 32, 31 } }" } }, function(w)
    A.same(SimSpellData.get(w, KIT).effects, {
      { type = "aura", aura = "dummy", base = 0, target = "caster" },
      { type = "trigger", base = 0, target = "caster", trigger = 900002 },
    })
  end)
end

local function test_a_retail_layout_stores_base_points_as_a_float_column_assumed()
  local db2 = db2With({
    spelleffect = "return { [41] = { SpellID = 900001, EffectIndex = 0, Effect = 2, EffectBasePointsF = 12.5, ImplicitTarget = {6, 0} } }",
  })
  W.withWindows("retail", { db2 = db2, index = { ["spelleffect.spellid"] = "return { [900001] = { 41 } }" } }, function(w)
    A.eq(SimSpellData.get(w, KIT).effects[1].base, 12.5)
  end)
end

local function test_a_literal_with_a_ground_effect_is_a_ground_spell_with_or_without_an_extract()
  local literal = { id = KIT, effects = { { type = "damage", base = 3, target = "areaDest", radius = 8 } } }
  W.withWindows("retail", {}, function(w)
    SimSpellData.put(w, literal)
    A.eq(SimSpellData.get(w, KIT).ground, true)
  end)
  withKit("retail", DB2, function(w)
    SimSpellData.put(w, literal)
    A.eq(SimSpellData.get(w, KIT).ground, true)
  end)
end

local function test_only_the_base_difficulty_rows_of_an_effect_play_assumed()
  local db2 = db2With({
    spelleffect = "return { [51] = { SpellID = 900001, EffectIndex = 0, Effect = 2, EffectBasePoints = 5, DifficultyID = 0, ImplicitTarget = {6, 0} },"
      .. " [52] = { SpellID = 900001, EffectIndex = 0, Effect = 2, EffectBasePoints = 50, DifficultyID = 1, ImplicitTarget = {6, 0} },"
      .. " [53] = { SpellID = 900001, EffectIndex = 0, Effect = 2, EffectBasePoints = 500, DifficultyID = 2, ImplicitTarget = {6, 0} },"
      .. " [54] = { SpellID = 900001, EffectIndex = 1, Effect = 2, EffectBasePoints = 7, ImplicitTarget = {6, 0} } }",
  })
  W.withWindows("retail", { db2 = db2, index = { ["spelleffect.spellid"] = "return { [900001] = { 54, 52, 51, 53 } }" } }, function(w)
    local effects = SimSpellData.get(w, KIT).effects
    A.same({ #effects, effects[1].base, effects[2].base }, { 2, 5, 7 }) -- a layout without the column keeps its rows
  end)
end

local function test_a_zero_cost_row_is_no_cost_assumed()
  local db2 = db2With({ spellpower = "return { [1] = { SpellID = 900001, PowerType = 0, ManaCost = 0 } }" }) -- retail Fireball: percent-costed
  withKit("retail", db2, function(w)
    A.eq(SimSpellData.get(w, KIT).cost, nil)
  end)
end

local function test_rage_cost_is_stored_times_ten_and_a_missing_cooldown_row_is_zero_assumed()
  local db2 = db2With({ spellpower = "return { [1] = { SpellID = 900001, PowerType = 1, ManaCost = 150 } }" })
  db2.spellcooldowns = nil
  W.withWindows("retail", { db2 = db2, index = INDEX }, function(w)
    local record = SimSpellData.get(w, KIT)
    A.same(record.cost, { type = "RAGE", amount = 15 })
    A.same({ record.cooldown, record.gcd }, { 0, 0 })
  end)
end

local function test_without_an_extract_get_returns_only_put_literals()
  W.withWindows("retail", {}, function(w)
    A.eq(SimSpellData.get(w, KIT), nil)
    SimSpellData.put(w, { id = KIT, name = "Literal", castTime = 0, effects = { { type = "damage", base = 3, target = "enemy" } } })
    A.same(SimSpellData.get(w, KIT), {
      id = KIT,
      name = "Literal",
      castTime = 0,
      cooldown = 0,
      gcd = 0,
      ground = false,
      effects = { { type = "damage", base = 3, target = "enemy" } },
    })
    SimSpellData.publish(w, KIT)
    A.same({ w.mock.spells[KIT].name, w.mock.spells[KIT].castTime }, { "Literal", 0 })
    SimSpellData.publish(w, 424242) -- no record: nothing written
    A.eq(w.mock.spells[424242], nil)
  end)
end

-- source: confirmed (retail 70688 SpellEffect rows) Frost Nova's root is aura 455; Charge and Thunder Clap carry Effect 3
-- (DUMMY), which is a typed effect that plays nothing; an energize of misc value 1 (rage) is stored times ten like a rage cost.
local function test_real_rows_root_aura_455_dummy_effect_3_and_energize_in_tenths_confirmed()
  local db2 = db2With({
    spelleffect = "return { [61] = { SpellID = 900001, EffectIndex = 0, Effect = 6, EffectAura = 455, ImplicitTarget = {22, 0} },"
      .. " [62] = { SpellID = 900001, EffectIndex = 1, Effect = 3, ImplicitTarget = {1, 0} },"
      .. " [63] = { SpellID = 900001, EffectIndex = 2, Effect = 30, EffectBasePointsF = 200, EffectMiscValue = 1, ImplicitTarget = {1, 0} },"
      .. " [64] = { SpellID = 900001, EffectIndex = 3, Effect = 30, EffectBasePointsF = 200, EffectMiscValue = 0, ImplicitTarget = {1, 0} } }",
  })
  W.withWindows("retail", { db2 = db2, index = { ["spelleffect.spellid"] = "return { [900001] = { 61, 62, 63, 64 } }" } }, function(w)
    A.same(SimSpellData.get(w, KIT).effects, {
      { type = "aura", aura = "root", base = 0, target = "areaSource" },
      { type = "dummy", base = 0, target = "caster" },
      { type = "energize", base = 20, target = "caster" },
      { type = "energize", base = 200, target = "caster" },
    })
    A.eq(w.unscripted["sim:effect:3"], nil)
  end)
end

return function()
  test_a_db2_spell_normalizes_units_and_fields_assumed()
  test_a_kit_literal_wins_for_effects_and_db2_for_numbers_assumed()
  test_a_kit_literals_cost_wins_over_the_extracts()
  test_get_caches_and_put_invalidates()
  test_ground_and_radius_come_from_the_effect_row_assumed()
  test_effect_and_aura_and_target_numbers_assumed()
  test_an_unlisted_aura_is_dummy_and_a_trigger_names_its_spell_assumed()
  test_a_retail_layout_stores_base_points_as_a_float_column_assumed()
  test_a_literal_with_a_ground_effect_is_a_ground_spell_with_or_without_an_extract()
  test_only_the_base_difficulty_rows_of_an_effect_play_assumed()
  test_a_zero_cost_row_is_no_cost_assumed()
  test_rage_cost_is_stored_times_ten_and_a_missing_cooldown_row_is_zero_assumed()
  test_real_rows_root_aura_455_dummy_effect_3_and_energize_in_tenths_confirmed()
  test_without_an_extract_get_returns_only_put_literals()
end
