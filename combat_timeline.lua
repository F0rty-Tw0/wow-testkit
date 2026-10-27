-- Timeline: a script of combat entries, each run at = seconds from now on the world clock (Combat.later, so w:advance and
-- s:advance drive it). Units are tokens (or actors) and resolve when the script is scheduled: a bad entry raises before any
-- entry is scheduled. Every entry calls one Resolve or Ai action, so numbers and spells are the script's own (R4).
--
-- entry = { at, <one action> }, the action being
--   damage    = { from, to, amount, spell?, school?, crit?, periodic?, ranged?, miss? }
--   heal      = { from, to, amount, spell, crit?, periodic? }
--   cast      = { from, spell, to?, castTime? }
--   aura      = { to, spell, from?, duration?, stacks?, absorb?, reduction?, immune?, harmful?, dispelName? }
--   interrupt = { from, to, spell }
--   kill      = unit
--   pull      = unit
local M = {}

local Actors = require("combat_actors")
local Ai = require("combat_ai")
local Combat = require("combat")
local Resolve = require("combat_resolve")

local DAMAGE_KEYS = { "amount", "school", "crit", "periodic", "ranged", "miss" }
local AURA_KEYS = { "duration", "stacks", "absorb", "reduction", "immune", "harmful", "dispelName" }

local function pick(from, keys, into)
  for _, key in ipairs(keys) do
    into[key] = from[key]
  end
  return into
end

-- Each action takes the entry's value and a unit(token, field) resolver, and returns the function the timer runs.
local ACTIONS = {
  damage = function(w, d, unit)
    local from, to = unit(d.from, "damage.from"), unit(d.to, "damage.to")
    return function()
      Resolve.damage(w, from, to, pick(d, DAMAGE_KEYS, { spellID = d.spell }))
    end
  end,
  heal = function(w, d, unit)
    local from, to = unit(d.from, "heal.from"), unit(d.to, "heal.to")
    return function()
      Resolve.heal(w, from, to, { amount = d.amount, spellID = d.spell, crit = d.crit, periodic = d.periodic })
    end
  end,
  cast = function(w, d, unit)
    local from, to = unit(d.from, "cast.from"), d.to and unit(d.to, "cast.to")
    return function()
      Resolve.cast(w, from, { spellID = d.spell, castTime = d.castTime, target = to })
    end
  end,
  aura = function(w, d, unit)
    local from, to = d.from and unit(d.from, "aura.from"), unit(d.to, "aura.to")
    return function()
      Resolve.aura(w, from, to, pick(d, AURA_KEYS, { spellID = d.spell }))
    end
  end,
  interrupt = function(w, d, unit)
    local from, to = unit(d.from, "interrupt.from"), unit(d.to, "interrupt.to")
    return function()
      Resolve.interrupt(w, from, to, d.spell)
    end
  end,
  kill = function(w, token, unit)
    local actor = unit(token, "kill")
    return function()
      Resolve.kill(w, actor)
    end
  end,
  pull = function(w, token, unit)
    local actor = unit(token, "pull")
    return function()
      Ai.pull(w, actor)
    end
  end,
}

-- The action key of an entry; raises unless there is exactly one.
local function actionOf(entry, where)
  local found
  for key in pairs(ACTIONS) do
    if entry[key] ~= nil then
      if found then
        error(where .. " must hold exactly one action; it has " .. found .. " and " .. key, 0)
      end
      found = key
    end
  end
  if not found then
    error(where .. " must hold exactly one action: damage, heal, cast, aura, interrupt, kill or pull", 0)
  end
  return found
end

-- Schedules the entries; label names the caller in errors (default "Timeline.run"). Entries with the same at run in list order.
function M.run(w, entries, label)
  label = label or "Timeline.run"
  local steps = {}
  for i, entry in ipairs(entries) do
    local where = string.format("%s: entry %d", label, i)
    if type(entry.at) ~= "number" or entry.at < 0 then
      error(where .. " needs a number 'at' of 0 or more (seconds from now)", 0)
    end
    local key = actionOf(entry, where)
    local function unit(token, field)
      local actor = type(token) == "table" and token or (token ~= nil and Actors.get(w, token))
      if not actor then
        error(string.format("%s: %s names no unit '%s'", where, field, tostring(token)), 0)
      end
      return actor
    end
    steps[i] = { at = entry.at, run = ACTIONS[key](w, entry[key], unit) }
  end
  for _, step in ipairs(steps) do
    Combat.later(w, step.at, step.run)
  end
end

return M
