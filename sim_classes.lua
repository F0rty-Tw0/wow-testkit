-- SimClasses: the Warrior and Mage kits (spec 7.4). apply puts the literal records of the world's flavor group
-- (sim_classes_data.lua) with the extract's numbers over them, marks each spell known, fills the action bar from slot 1 in
-- kit order and sets the class's proc rules (w.sim.procRules, read by SimProcs). install applies the kit of w.sim.class,
-- applies it again on a world reset (which may change the class; the changed bar slots fire ACTIONBAR_SLOT_CHANGED) and on
-- a reload (whose restored class may differ; no event).
local M = {}

local Combat = require("combat")
local Data = require("sim_classes_data")
local SimSpellData = require("sim_spell_data")
local SimState = require("sim_state")
local State = require("game.state")

-- source: assumed (spec 7.4 groups; mists inferred) the flavor -> the kit group: retail plays the modern kit, the rest the
-- classic one. source: confirmed (forever 70862 is a 1.60 client: no Blizzard 190356, 5302 is Defensive State, Heroic
-- Strike 78, Overpower 7384 and Blizzard 10 present) forever is classic.
M.FLAVOR_GROUP = { retail = "modern", forever = "classic", mists = "classic", tbc = "classic", vanilla = "classic" }

M.KITS = Data.KITS

-- The spells and bar slots of the kit applied last leave: the spells stop being known, the slots empty.
local function clear(w)
  for slot, id in ipairs(w.sim.kitIds or {}) do
    local entry = w.mock.spells[id] -- a scenario may have replaced w.mock.spells wholesale
    if entry then
      entry.known = nil
    end
    w.mock.actions[slot] = nil
  end
  w.sim.kitIds, w.sim.procRules = nil, nil
end

-- Puts the record, publishes it into w.mock.spells, knows it and bars it at slot.
local function learn(w, slot, record)
  SimSpellData.put(w, record)
  SimSpellData.publish(w, record.id)
  w.mock.spells[record.id].known = true
  w.mock.actions[slot] = { type = "spell", id = record.id, texture = SimSpellData.get(w, record.id).icon }
end

-- Replaces the kit with the one of class for the sim flavor's group: the known spells, the bar and the proc rules. actor is
-- the player (the kit is its own).
function M.apply(w, _actor, class)
  clear(w)
  local group = M.FLAVOR_GROUP[w.flavor]
  local ids = {}
  for slot, record in ipairs(M.KITS[class][group]) do
    learn(w, slot, record)
    ids[slot] = record.id
  end
  w.sim.kitIds = ids
  w.sim.procRules = State.merge({}, Data.PROCS[class][group])
end

local function applyClass(w)
  M.apply(w, w.sim.player, w.sim.class)
end

-- source: assumed (no client trace) a kit that changed the known spells fires SPELLS_CHANGED once, then
-- ACTIONBAR_SLOT_CHANGED(slot) for each slot whose spell changed, ascending; an identical kit fires nothing.
local function announce(w, before, after)
  local slots = {}
  for slot = 1, math.max(#before, #after) do
    if before[slot] ~= after[slot] then
      slots[#slots + 1] = slot
    end
  end
  if #slots == 0 then
    return
  end
  Combat.fire(w, "SPELLS_CHANGED")
  for _, slot in ipairs(slots) do
    Combat.fire(w, "ACTIONBAR_SLOT_CHANGED", slot)
  end
end

-- The kit of the world's current class after a world reset (which may change the class): the bar events say what changed
-- (the Blizzard buttons and bar addons redraw from them).
function M.reset(w)
  local before = w.sim.kitIds or {}
  applyClass(w)
  announce(w, before, w.sim.kitIds)
end

-- Applies the kit of the world's class and hooks the reset and the reload (the class is re-read each time). The first
-- install and a reload's restore fire no event: nothing was on screen before them.
function M.install(w)
  applyClass(w)
  table.insert(w.sim.hooks.reset, M.reset)
  SimState.persist(w, "classes", {
    export = function()
      return {}
    end,
    restore = applyClass,
  })
end

return M
