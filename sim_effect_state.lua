-- SimEffectState: what the effects keep in w.sim and show. fx is the ring of events the world reads (two seconds), areas the
-- persistent areas, spellAuras a record per aura a spell put on an actor (its end is logged here, Auras.remove logs
-- nothing). snapshot is the effects list of the sim world; export and restore carry the areas and the records through a
-- hot reload.
local M = {}

local Combat = require("combat")
local Log = require("combat_log")
local SimRange = require("sim_range")
local SimState = require("sim_state")
local State = require("game.state")

local RULES = {
  -- source: assumed (spec 7.3) the seconds an event stays in the ring the world reads.
  RING = 2,
  -- source: assumed (spec 7.3) only root and stun have a scene effect.
  SHOWN = { root = true, stun = true },
}

-- Adds an event to the ring the world reads.
function M.record(w, kind, fields)
  fields.kind, fields.t = kind, w.now
  table.insert(w.sim.fx, fields)
end

-- The key of an aura record: the instance ids count per actor, so the actor's GUID goes in front.
function M.auraKey(guid, instanceID)
  return guid .. "/" .. instanceID
end

-- Drops the events older than the ring keeps.
function M.prune(w)
  local fx = w.sim.fx
  while fx[1] and fx[1].t < w.now - RULES.RING do
    table.remove(fx, 1)
  end
end

local function sortedKeys(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  table.sort(keys)

  return keys
end

-- The events of the last two seconds, then one ground effect per area, then one aura effect per root or stun aura.
function M.snapshot(w)
  local sim, out = w.sim, {}
  for _, event in ipairs(sim.fx) do
    if event.t >= w.now - RULES.RING then
      out[#out + 1] = State.merge({}, event)
    end
  end
  for _, area in ipairs(sim.areas) do
    out[#out + 1] = { kind = "ground", at = SimRange.copy(area.at), radius = area.radius, spellID = area.spellID }
  end
  for _, key in ipairs(sortedKeys(sim.spellAuras)) do
    local held = sim.spellAuras[key]
    if RULES.SHOWN[held.style] then
      out[#out + 1] = { kind = "aura", guid = held.targetGuid, spellID = held.spellID, style = held.style }
    end
  end

  return out
end

-- The sim aura that went: SPELL_AURA_REMOVED once, and its record is dropped.
local function onAura(w, actor, update)
  for _, id in ipairs(update.removedAuraInstanceIDs or {}) do
    local key = M.auraKey(actor.guid, id)
    local held = w.sim.spellAuras[key]
    if held then
      w.sim.spellAuras[key] = nil
      local caster = w.combat.actors[held.casterGuid]
      Log.emit(w, "SPELL_AURA_REMOVED", caster, actor, { spellID = held.spellID, auraType = caster == actor and "BUFF" or "DEBUFF" })
    end
  end
end

-- An actor that leaves the world takes its aura records with it (it logs no removal).
local function onDespawn(w, actor)
  for key, held in pairs(w.sim.spellAuras) do
    if held.targetGuid == actor.guid then
      w.sim.spellAuras[key] = nil
    end
  end
end

-- A world reset clears the areas and the ring (the actors and their auras go with the reset itself).
function M.reset(w)
  w.sim.areas, w.sim.fx = {}, {}
end

-- source: assumed (a reload drops the run and the projectiles) the areas keep their absolute times and the aura records
-- come back with the auras (Auras.restore).
local function export(w)
  return { areas = State.merge({}, w.sim.areas), auras = State.merge({}, w.sim.spellAuras) }
end

-- Whether the actor with guid wears the aura whose record key is key.
local function wears(w, guid, key)
  local actor = w.combat.actors[guid]
  for _, aura in ipairs(actor and actor.auras or {}) do
    if M.auraKey(guid, aura.auraInstanceID) == key then
      return true
    end
  end

  return false
end

-- Keeps the records of the auras that came back: Auras.restore leaves off one that had run out, and its record goes too.
local function restore(w, data)
  w.sim.areas, w.sim.spellAuras = data.areas, {}
  for key, held in pairs(data.auras) do
    if wears(w, held.targetGuid, key) then
      w.sim.spellAuras[key] = held
    end
  end
end

-- Adds the effect state, logs the end of sim auras and registers the reload state.
function M.install(w)
  local sim = w.sim
  sim.fx, sim.areas, sim.spellAuras = {}, {}, {}
  Combat.listen(w, "aura", function(actor, update)
    onAura(w, actor, update)
  end)
  Combat.listen(w, "despawn", function(actor)
    onDespawn(w, actor)
  end)
  SimState.persist(w, "effects", { export = export, restore = restore })
end

return M
