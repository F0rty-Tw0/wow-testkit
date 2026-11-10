-- Real-extract spell data proof (a script, not a suite test): SimSpellData.get over known Warrior and Mage spells from a
-- client extract's DB2 export, printed so Task 5.6's kit literals can be aligned with the real numbers.
-- Usage (python tools/run51.py --script): proof_spells.lua <flavor> <extract-dir>
-- Prints `PROOF <id> <name> <field>=<value> ...` per spell; exits 1 when a spell has an effect id outside
-- SimSpellData.EFFECT (counted in w.unscripted["sim:effect:<n>"]) or no record at all.
local flavor, dir = ...
local Client = require("client")
local SimSpellData = require("sim_spell_data")
local World = require("world")

local print = print

-- The kit of each flavor group (sim_classes_data.lua): Charge, Thunder Clap, Fireball, Frost Nova, then retail Slam,
-- Revenge, Blizzard 190356; tbc Heroic Strike, Overpower, Blizzard 10.
local SPELLS = { retail = { 100, 6343, 133, 122, 1464, 6572, 190356 }, tbc = { 100, 6343, 133, 122, 78, 7384, 10 } }
local FIELDS = { "school", "castTime", "cooldown", "gcd", "duration", "minRange", "maxRange" }

local function effectText(effect)
  local parts = { effect.type, "base=" .. effect.base, "target=" .. tostring(effect.target) }
  for _, key in ipairs({ "aura", "radius", "period", "trigger" }) do
    parts[#parts + 1] = effect[key] and (key .. "=" .. effect[key]) or nil
  end

  return "{" .. table.concat(parts, ",") .. "}"
end

local function costText(cost)
  return cost and (cost.type .. ":" .. cost.amount) or "none"
end

local function describe(record)
  local parts = {}
  for _, field in ipairs(FIELDS) do
    parts[#parts + 1] = field .. "=" .. tostring(record[field])
  end
  parts[#parts + 1] = "cost=" .. costText(record.cost)
  parts[#parts + 1] = "ground=" .. tostring(record.ground)
  for index, effect in ipairs(record.effects) do
    parts[#parts + 1] = "effect" .. index .. "=" .. effectText(effect)
  end

  return table.concat(parts, " ")
end

local function prove(w, ids)
  local failures = 0
  for _, id in ipairs(ids) do
    local record = SimSpellData.get(w, id)
    if record then
      print("PROOF " .. id .. " " .. tostring(record.name) .. " " .. describe(record))
    else
      print("MISSING " .. id)
      failures = failures + 1
    end
  end

  return failures
end

local extract = assert(Client.load(dir, flavor), "no extract manifest in " .. tostring(dir))
local w = World.new({ flavor = flavor, client = extract })
local ok, failures = pcall(prove, w, SPELLS[flavor] or SPELLS.tbc)
local unknown = {}
for name, count in pairs(w.unscripted) do
  if name:find("^sim:effect:") then
    unknown[#unknown + 1] = name .. " x" .. count
  end
end
w:destroy()
if not ok then
  error(failures, 0)
end
table.sort(unknown)
for _, line in ipairs(unknown) do
  print("UNSCRIPTED " .. line)
end

return (failures > 0 or #unknown > 0) and 1 or 0
