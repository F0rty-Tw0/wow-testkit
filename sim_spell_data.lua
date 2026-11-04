-- SimSpellData: the normalized spell record (spec 7.1) the cast pipeline plays. The numbers come from the client
-- extract's DB2 rows (name, icon, school, cast time, ranges, cooldown, GCD, cost, duration); the effects come from a kit
-- literal registered with put, else from the SpellEffect rows. Without an extract only put literals answer. Records are
-- cached in w.sim.spellData (not exported; rebuilt on demand).
local M = {}

local BlizzardData = require("blizzard_data")
local CombatSpells = require("combat_spells")
local State = require("game.state")
local WorldApi = require("world_api")

local RULES = {
  -- source: assumed (TrinityCore SharedDefines numbers; Task 5.1 Step 6 checks them against real rows) SpellEffect.Effect
  -- -> record effect type. An id not listed is skipped and counted in w.unscripted["sim:effect:<n>"].
  EFFECT = { [2] = "damage", [6] = "aura", [17] = "damage", [27] = "persistent", [30] = "energize", [96] = "charge", [64] = "trigger" },
  -- source: assumed (TrinityCore SharedDefines numbers; Step 6 checks them) SpellEffect.EffectAura -> record aura; any
  -- other aura is "dummy".
  AURA = { [3] = "periodic", [12] = "stun", [26] = "root" },
  -- source: assumed (TrinityCore SharedDefines numbers: TARGET_UNIT_CASTER 1, TARGET_UNIT_TARGET_ENEMY 6,
  -- TARGET_UNIT_SRC_AREA_ENEMY 22 and 16, TARGET_DEST_DEST 18, TARGET_DEST_TARGET_ENEMY 15; Step 6 checks them)
  -- ImplicitTarget[1] -> record target.
  TARGET = { [1] = "caster", [6] = "enemy", [22] = "areaSource", [16] = "areaSource", [15] = "areaDest", [18] = "areaDest" },
  -- source: assumed (DB2 SpellPower.PowerType; Step 6 checks Heroic Strike) 0 is mana, 1 is rage.
  POWER = { [0] = "MANA", [1] = "RAGE" },
  -- source: assumed (Step 6 checks Heroic Strike) a rage cost is stored times ten.
  RAGE_SCALE = 10,
  -- source: confirmed (retail 70688 extract: no (SpellID, EffectIndex) pair repeats among the DifficultyID 0 rows);
  -- assumed (a layout without the column has base rows only) a SpellEffect row of another difficulty is skipped.
  BASE_DIFFICULTY = 0,
  -- The record fields publish copies into w.mock.spells (SimRange.IsSpellInRange reads maxRange and minRange there).
  PUBLISHED = { "name", "icon", "castTime", "minRange", "maxRange" },
}

M.EFFECT, M.AURA = RULES.EFFECT, RULES.AURA

-- Kit literals per world (put). Weak by world, so a bare window world needs no w.sim; every world's install puts its own.
local literals = setmetatable({}, { __mode = "k" })

function M.target(n)
  return RULES.TARGET[n]
end

-- An array column's first element (the hostile one); a scalar column answers itself.
local function first(value)
  if type(value) == "table" then
    return value[1]
  end

  return value
end

local function row(w, name, id)
  local rows = id and BlizzardData.table(w, name)

  return rows and rows[id] or nil
end

local function firstBy(w, name, spellID)
  return BlizzardData.rowsBy(w, name, "SpellID", spellID)[1]
end

-- The ms or yards a DB2 lookup row holds in field (SpellCastTimes.Base, SpellDuration.Duration), or nil.
local function lookup(w, name, id, field)
  local found = row(w, name, id)

  return found and found[field] or nil
end

local function radiusOf(w, effect)
  local index = first(effect.EffectRadiusIndex)
  if not index or index == 0 then
    return nil
  end

  return lookup(w, "SpellRadius", index, "Radius")
end

local function positive(value)
  return value and value > 0 and value or nil
end

-- The record aura of an aura or persistent effect row, "dummy" for an aura the sim does not know; nil for any other effect.
local function auraOf(kind, effect)
  local holdsAura = kind == "aura" or kind == "persistent"
  if not (holdsAura and effect.EffectAura) then
    return nil
  end

  return RULES.AURA[effect.EffectAura] or "dummy"
end

-- One record effect from a SpellEffect row, or nil (and a count) when its Effect id is not scripted.
local function effectOf(w, effect)
  local kind = M.EFFECT[effect.Effect]
  if not kind then
    WorldApi.markUnscripted(w, "sim:effect:" .. tostring(effect.Effect))

    return nil
  end
  -- source: assumed (Step 6: the retail layout has EffectBasePointsF only, the classic ones EffectBasePoints only)
  local base = effect.EffectBasePoints or effect.EffectBasePointsF or 0
  local out = { type = kind, base = base, target = M.target(first(effect.ImplicitTarget)) }
  out.aura = auraOf(kind, effect)
  out.radius = radiusOf(w, effect)
  out.period = positive(effect.EffectAuraPeriod)
  out.trigger = positive(effect.EffectTriggerSpell)

  return out
end

local function byEffectIndex(a, b)
  return (a.EffectIndex or 0) < (b.EffectIndex or 0)
end

local function isBaseRow(effect)
  return effect.DifficultyID == nil or effect.DifficultyID == RULES.BASE_DIFFICULTY
end

local function effectsOf(w, id)
  local rows = BlizzardData.rowsBy(w, "SpellEffect", "SpellID", id)
  table.sort(rows, byEffectIndex)
  local effects = {}
  for _, effect in ipairs(rows) do
    if isBaseRow(effect) then
      effects[#effects + 1] = effectOf(w, effect)
    end
  end

  return effects
end

local function hasGround(effects)
  for _, effect in ipairs(effects or {}) do
    if effect.target == "areaDest" then
      return true
    end
  end

  return false
end

-- { type, amount } from the spell's first SpellPower row, or nil for a free spell, a power the sim does not play, or a
-- row without a flat cost. source: assumed (Step 6: retail Fireball and Frost Nova rows hold ManaCost 0, their cost is a
-- percentage this export does not carry, so a kit literal states it).
local function costOf(w, id)
  local power = firstBy(w, "SpellPower", id)
  local kind = power and RULES.POWER[power.PowerType]
  local amount = positive(power and power.ManaCost)
  if not (kind and amount) then
    return nil
  end

  local flat = kind == "RAGE" and amount / RULES.RAGE_SCALE or amount

  return { type = kind, amount = flat }
end

-- source: assumed (Step 6 checks) RecoveryTime is the spell's own cooldown in ms, CategoryRecoveryTime stands in when it
-- is 0, and StartRecoveryTime is the GCD; a spell with no SpellCooldowns row has neither.
local function cooldownsOf(w, id)
  local found = firstBy(w, "SpellCooldowns", id)
  if not found then
    return nil, nil
  end
  local own = positive(found.RecoveryTime) or positive(found.CategoryRecoveryTime) or 0

  return own, found.StartRecoveryTime or 0
end

-- The DB2-derived fields of spell id (effects included), or nil without a SpellName row.
local function fromDb2(w, id)
  local name = CombatSpells.extractName(w, id)
  if not name then
    return nil
  end
  local misc = row(w, "SpellMisc", id) or {}
  local range = row(w, "SpellRange", misc.RangeIndex) or {}
  local cooldown, gcd = cooldownsOf(w, id)

  return {
    id = id,
    name = name,
    icon = misc.SpellIconFileDataID,
    school = misc.SchoolMask,
    castTime = lookup(w, "SpellCastTimes", misc.CastingTimeIndex, "Base"),
    cooldown = cooldown,
    gcd = gcd,
    duration = lookup(w, "SpellDuration", misc.DurationIndex, "Duration"),
    minRange = first(range.RangeMin),
    maxRange = first(range.RangeMax),
    cost = costOf(w, id),
    effects = effectsOf(w, id),
  }
end

-- source: assumed (retail effect scaling is not modeled; the kit literal states the amounts we play) a literal's
-- effects replace the DB2 effects; every other DB2 number replaces the literal's.
local function merge(literal, derived)
  local record = State.merge({}, literal or {})
  for key, value in pairs(derived) do
    if key ~= "effects" or not record.effects then
      record[key] = value
    end
  end
  record.cooldown, record.gcd = record.cooldown or 0, record.gcd or 0
  if record.ground == nil then
    record.ground = hasGround(record.effects)
  end

  return record
end

local function build(w, id)
  local literal = literals[w] and literals[w][id]
  local derived = fromDb2(w, id)
  if not derived and not literal then
    return nil
  end

  return merge(literal, derived or {})
end

local function cache(w)
  if not w.sim then
    return nil
  end
  w.sim.spellData = w.sim.spellData or {}

  return w.sim.spellData
end

-- The normalized record of spell id, or nil when neither the extract nor a put literal knows it. Cached in
-- w.sim.spellData once the sim exists.
function M.get(w, id)
  local store = cache(w)
  if store and store[id] then
    return store[id]
  end
  local record = build(w, id)
  if store then
    store[id] = record
  end

  return record
end

-- Registers a kit literal (record.id names the spell); it fills what the extract lacks and states the effects.
function M.put(w, record)
  literals[w] = literals[w] or {}
  literals[w][record.id] = State.merge({}, record)
  local store = cache(w)
  if store then
    store[record.id] = nil
  end
end

-- Writes name, icon, castTime, minRange and maxRange of spell id into w.mock.spells[id], never over a field the
-- scenario set.
function M.publish(w, id)
  local record = M.get(w, id)
  if not record then
    return
  end
  local target = w.mock.spells[id] or {}
  w.mock.spells[id] = target
  for _, field in ipairs(RULES.PUBLISHED) do
    if target[field] == nil then
      target[field] = record[field]
    end
  end
end

return M
