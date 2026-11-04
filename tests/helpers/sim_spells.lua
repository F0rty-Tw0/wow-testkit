-- Sim spell test helper: kit spell records and a sim world where they are known. Tests never read a client extract or
-- install.
local SH = require("tests.helpers.sim_combat")
local SimSpellData = require("sim_spell_data")

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

return M
