-- Sim spell test helper: kit spell records and a sim world where they are known. Tests never read a client extract or
-- install.
local SH = require("tests.helpers.sim_combat")
local Actors = require("combat_actors")
local SimSpellData = require("sim_spell_data")
local SimWorld = require("sim_world")

local M = {}

M.FLAVORS = SH.FLAVORS

-- A record with the kit defaults; over's fields replace them.
function M.record(over)
  local record = { id = 900001, name = "Kit Bolt", castTime = 0, cooldown = 0, gcd = 0, minRange = 0, maxRange = 40, school = 1, effects = {} }
  for key, value in pairs(over or {}) do
    record[key] = value
  end

  return record
end

-- Puts, publishes and marks known every record of recs on world w.
function M.install(w, recs)
  for _, record in ipairs(recs) do
    SimSpellData.put(w, record)
    SimSpellData.publish(w, record.id)
    w.mock.spells[record.id].known = true
  end
end

-- Runs fn(w, s, player) on a sim world where recs are known spells.
function M.withSpells(flavor, recs, fn)
  SH.withSim(flavor, function(w, s, player)
    M.install(w, recs)
    fn(w, s, player)
  end)
end

-- A hostile Foe at (x, y) (default (0, 10)) that becomes the player's target.
function M.target(w, player, x, y)
  local foe = SH.foe(w, x or 0, y or 10)
  Actors.setTarget(w, player, foe)

  return foe
end

-- The subevents the effects logged, the cast lines left out.
function M.subevents(w)
  local out = {}
  for _, entry in ipairs(w.combat.log.entries) do
    if not entry[2]:find("^SPELL_CAST") then
      out[#out + 1] = entry[2]
    end
  end

  return out
end

-- How many log lines of subevent name the actor with guid took (dest GUID is entry[8]).
function M.hitsOn(w, subevent, guid)
  local n = 0
  for _, entry in ipairs(w.combat.log.entries) do
    if entry[2] == subevent and entry[8] == guid then
      n = n + 1
    end
  end

  return n
end

function M.effectsOfKind(w, kind)
  local out = {}
  for _, effect in ipairs(SimWorld.build(w).effects) do
    if effect.kind == kind then
      out[#out + 1] = effect
    end
  end

  return out
end

return M
