-- SimSpellCooldowns: the cooldown and global-cooldown clocks of the cast pipeline (spec 7.2). The clocks live in w.sim as
-- plain data (cooldowns[id] = { start, duration }, gcdEnd, gcdShown) and in w.mock.spells[id].cooldown for the readers
-- (C_Spell.GetSpellCooldown). SimSpells starts them with stamp and gives a dropped cast's GCD back with release.
local M = {}

local Combat = require("combat")
local SimSpellData = require("sim_spell_data")

local MS = 1000

-- The world-clock second the spell's cooldown started and how many seconds it lasts; 0, 0 when it has none.
function M.get(w, spellID)
  local cooldown = w.sim.cooldowns[spellID]
  if not cooldown then
    return 0, 0
  end

  return cooldown.start, cooldown.duration
end

local function mirror(w, id, start, duration)
  SimSpellData.publish(w, id)
  local entry = w.mock.spells[id] or {}
  w.mock.spells[id] = entry
  entry.cooldown = { start = start, duration = duration, enabled = true }
end

local function startOwn(w, rec)
  local seconds = (rec.cooldown or 0) / MS
  if seconds <= 0 then
    return false
  end
  w.sim.cooldowns[rec.id] = { start = w.now, duration = seconds }
  mirror(w, rec.id, w.now, seconds)

  return true
end

local function startGcd(w, rec)
  local seconds = (rec.gcd or 0) / MS
  if seconds <= 0 then
    return false
  end
  w.sim.gcdEnd = w.now + seconds
  w.sim.gcdShown = { spell = rec.id, start = w.now, duration = seconds }
  mirror(w, rec.id, w.now, seconds)

  return true
end

-- Takes the GCD off the spell that shows it. Its own cooldown never runs here: a spell on cooldown cannot be cast, and a
-- reset clears the cooldowns first.
function M.release(w)
  local shown = w.sim.gcdShown
  local entry = shown and w.mock.spells[shown.spell]
  w.sim.gcdShown = nil
  if not entry then
    return
  end
  entry.cooldown = nil
  Combat.fire(w, "ACTIONBAR_UPDATE_COOLDOWN")
  Combat.fire(w, "SPELL_UPDATE_COOLDOWN")
end

-- Starts the GCD and/or the spell's own cooldown (the own one wins the mirror) and announces them once. Answers whether
-- the GCD started.
function M.stamp(w, rec, withGcd, withOwn)
  local gcd = withGcd and startGcd(w, rec)
  local own = withOwn and startOwn(w, rec)
  if gcd or own then
    Combat.fire(w, "ACTIONBAR_UPDATE_COOLDOWN")
    Combat.fire(w, "SPELL_UPDATE_COOLDOWN")
  end

  return gcd
end

-- A world reset also clears every cooldown. source: assumed (a reset is a fresh login).
function M.reset(w)
  for id in pairs(w.sim.cooldowns) do
    w.mock.spells[id].cooldown = nil
  end
  w.sim.cooldowns, w.sim.gcdEnd = {}, 0
  M.release(w)
end

local function byId(a, b)
  return a.id < b.id
end

-- The running cooldowns as a list, the GCD end and the spell that shows the GCD.
function M.export(w)
  local running = {}
  for id, cooldown in pairs(w.sim.cooldowns) do
    if cooldown.start + cooldown.duration > w.now then
      running[#running + 1] = { id = id, start = cooldown.start, duration = cooldown.duration }
    end
  end
  table.sort(running, byId)

  return { cooldowns = running, gcdEnd = w.sim.gcdEnd, gcdShown = w.sim.gcdShown }
end

-- The GCD comes back on its spell's readers only while it runs: a dropped cast's GCD was never kept (gcdEnd is the one
-- before it), and the cooldowns follow so that a spell's own cooldown wins the mirror, as in stamp.
function M.restore(w, data)
  local shown = data.gcdShown
  w.sim.gcdEnd = data.gcdEnd
  if shown and data.gcdEnd > w.now then
    w.sim.gcdShown = shown
    mirror(w, shown.spell, shown.start, shown.duration)
  end
  for _, item in ipairs(data.cooldowns) do
    w.sim.cooldowns[item.id] = { start = item.start, duration = item.duration }
    mirror(w, item.id, item.start, item.duration)
  end
end

function M.install(w)
  w.sim.cooldowns, w.sim.gcdEnd = {}, 0
end

return M
