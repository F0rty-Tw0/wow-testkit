-- SimEffectArea: the ground area a persistent effect leaves (Blizzard) and the hostiles within reach of a point. An area is
-- plain data in w.sim.areas; step ticks the due ones from the frame hook and drops the ones that ran out.
local M = {}

local Resolve = require("combat_resolve")
local SimRange = require("sim_range")

local MS = 1000

local RULES = {
  -- source: assumed (spec 7.3) a persistent area ticks every second, the first one a second after the cast.
  TICK = 1,
  -- source: assumed (float slack) a tick, an edge or a deadline that falls within this much counts as reached.
  EPS = 1e-6,
}

-- The living hostiles within radius yards of center ({ x, y }), measured from a point with no reach of its own.
-- source: assumed (spec 7.3) the edge counts; friends and the dead are spared.
function M.around(w, center, radius)
  local origin = { pos = center, reach = 0 }
  local found = {}
  for _, guid in ipairs(w.combat.order) do
    local actor = w.combat.actors[guid]
    local hostile = actor.isEnemy and not actor.isDead
    local gap = SimRange.distance(origin, actor)
    if hostile and gap <= radius + RULES.EPS then
      found[#found + 1] = actor
    end
  end

  return found
end

-- source: assumed (spec 7.3) a persistent area lasts the spell's duration and ticks its damage on every hostile inside.
-- Adds the area of rec's effect (radius) at center for caster; amount is the damage of each tick.
function M.add(w, caster, rec, effect, center, amount)
  table.insert(w.sim.areas, {
    at = SimRange.copy(center),
    radius = effect.radius or 0,
    spellID = rec.id,
    school = rec.school,
    casterGuid = caster.guid,
    nextTick = w.now + RULES.TICK,
    endTime = w.now + (rec.duration or 0) / MS,
    base = amount,
  })
end

local function tick(w, area)
  local caster = w.combat.actors[area.casterGuid]
  if not caster then
    return
  end
  for _, victim in ipairs(M.around(w, area.at, area.radius)) do
    local spec = { amount = area.base, spellID = area.spellID, school = area.school, periodic = true }
    Resolve.damage(w, caster, victim, spec)
  end
end

-- Runs the ticks that are due; returns whether the area is still there.
local function stepArea(w, area)
  local eps = RULES.EPS
  while area.nextTick <= area.endTime + eps and w.now + eps >= area.nextTick do
    tick(w, area)
    area.nextTick = area.nextTick + RULES.TICK
  end

  return w.now + eps < area.endTime
end

-- One sim frame: every due tick, then the areas that ended leave.
function M.step(w)
  local live = {}
  for _, area in ipairs(w.sim.areas) do
    local running = stepArea(w, area)
    if running then
      live[#live + 1] = area
    end
  end
  w.sim.areas = live
end

return M
