-- SimGround: the targeting mode of a ground spell (spec 7.6). SimSpells opens it (w.sim.seams.ground) when a ground spell is
-- cast with no point; a left click on the ground then casts at that point, a right click, Esc (SpellStopCasting or
-- SpellStopTargeting) or a stun ends it, and a click on a unit is swallowed so the target stays. The mode is plain data in
-- w.sim.targeting = { spellID, radius }; SimSpells.cast with a point is still the only entry that plays the spell, so every
-- rule (range, cooldown, power) is the pipeline's, and a failed cast leaves the mode as it is.
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local SimRange = require("sim_range")
local SimSpellChecks = require("sim_spell_checks")
local SimSpells = require("sim_spells")
local SimState = require("sim_state")
local State = require("game.state")
local define = State.define

local LEFT = "LeftButton"
local RIGHT = "RightButton"
local CHANGED = "CURRENT_SPELL_CAST_CHANGED"

-- The radius of the first effect that lands on the clicked point, for the circle the viewer draws.
local function radiusOf(rec)
  for _, effect in ipairs(rec.effects or {}) do
    if effect.target == "areaDest" then
      return effect.radius or 0
    end
  end

  return 0
end

-- source: assumed (spec 7.6; the event's argument is the client's cancelledCast) CURRENT_SPELL_CAST_CHANGED fires once
-- when the mode opens (false), once when it ends by a cancel (true) and once when it ends by a cast (false).
local function leave(w, cancelled)
  if not w.sim.targeting then
    return false
  end
  w.sim.targeting = nil
  Combat.fire(w, CHANGED, cancelled)

  return true
end

-- Opens the mode for rec, replacing the one that was open. The seams.ground function.
function M.enter(w, rec)
  w.sim.targeting = { spellID = rec.id, radius = radiusOf(rec) }
  Combat.fire(w, CHANGED, false)
end

-- SpellStopTargeting: cancels the mode. Returns whether there was one.
function M.stop(w)
  return leave(w, true)
end

-- Casts the targeting spell at point; the mode ends with a cast that started and stays after one that failed.
local function castAt(w, point)
  local started = SimSpells.cast(w, w.sim.player, w.sim.targeting.spellID, nil, SimRange.copy(point))
  if started then
    leave(w, false)
  end

  return started
end

-- source: assumed (spec 7.6 state table) in the mode a left click casts at the ground point or, on a unit, does nothing; a
-- right click cancels; hovers and the other buttons go on to SimTarget. Returns handled, changed.
function M.pointer(w, kind, world, button)
  local pressed = button or LEFT
  local idle = not w.sim.targeting or kind ~= "click" or not world
  if idle or (pressed ~= LEFT and pressed ~= RIGHT) then
    return false, false
  end
  if pressed == RIGHT then
    return true, M.stop(w)
  end
  local started = world.ground and castAt(w, world.ground)

  return true, started == true
end

-- source: assumed (spec 7.6 state table) a stun cancels the mode; walking does not.
function M.step(w)
  if w.sim.targeting and SimSpellChecks.isStunned(w.sim.player) then
    M.stop(w)
  end
end

local function export(w)
  local mode = w.sim.targeting

  return mode and { spellID = mode.spellID, radius = mode.radius } or nil
end

local function restore(w, data)
  w.sim.targeting = { spellID = data.spellID, radius = data.radius }
end

local function defineFakes(w)
  define(w, "SpellIsTargeting", function()
    return w.sim.targeting ~= nil
  end)
  define(w, "SpellStopTargeting", function()
    return M.stop(w)
  end)
  define(w, "SpellTargetUnit", function(unit)
    local actor = Actors.get(w, unit)
    if w.sim.targeting and actor then
      castAt(w, actor.pos)
    end
  end)
  define(w, "SpellStopCasting", function()
    local casting = SimSpells.stop(w, w.sim.player)
    local targeting = M.stop(w)

    return casting or targeting
  end)
end

-- Adds the mode, hangs the pointer and the ground seam, defines the fakes (SpellStopCasting now ends the mode too) and hooks
-- the frame, the reset and the reload.
function M.install(w)
  w.sim.targeting = nil
  w.sim.seams.ground = M.enter
  table.insert(w.sim.seams.pointer, M.pointer)
  table.insert(w.sim.hooks.frame, M.step)
  table.insert(w.sim.hooks.reset, M.stop)
  defineFakes(w)
  SimState.persist(w, "ground", { export = export, restore = restore })
end

return M
