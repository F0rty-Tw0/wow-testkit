-- Casts and channels on actors. A cast or channel is the record Units' UnitCastingInfo / UnitChannelInfo read from the
-- actor (actor.cast, actor.channel); each step writes or clears it and emits the "cast" hook with the phase, which
-- combat_events turns into UNIT_SPELLCAST_* events. Every duration is scenario data: spec.duration (seconds), else the
-- spell record's castTime (milliseconds).
local M = {}

local Actors = require("combat_actors")
local Combat = require("combat")
local Spells = require("combat_spells")

local MS = 1000

-- Seconds the cast or channel lasts, from the spec or the spell's castTime; raises when scenario data gives neither.
local function secondsOf(info, spec, level)
  local seconds = spec.duration or (info.castTime and info.castTime / MS)
  if not seconds then
    error(string.format("combat: spell %d has no castTime; give the cast a duration", info.spellID), level + 1)
  end
  return seconds
end

local function start(w, actor, key, spec, level)
  if actor.cast or actor.channel then
    error("combat: " .. tostring(actor.name) .. " is already casting", level + 1)
  end
  local info = Spells.info(w, spec.spellID)
  local startMs = w.now * MS
  local record = {
    name = info.name,
    displayName = info.name,
    textureID = info.iconID,
    startTimeMs = startMs,
    endTimeMs = startMs + secondsOf(info, spec, level + 1) * MS,
    isTradeskill = false,
    notInterruptible = spec.notInterruptible == true,
    castGUID = Actors.newCastGuid(w, spec.spellID),
    spellID = spec.spellID,
  }
  if key == "cast" then
    record.castID, record.castingSpellID = record.castGUID, spec.spellID
  end
  actor[key] = record
  return record
end

-- Clears the record before the events fire, so a handler of the end sees the unit as no longer casting.
local function finishWith(w, actor, key, phases, interruptedBy)
  local record = actor[key]
  if not record then
    return
  end
  actor[key] = nil
  record.interruptedBy = interruptedBy and interruptedBy.guid or nil
  for _, phase in ipairs(phases) do
    Combat.emit(w, "cast", actor, phase, record)
  end
end

-- spec: { spellID, duration?, notInterruptible? }. Writes actor.cast and emits START. Returns the record.
function M.begin(w, actor, spec)
  local record = start(w, actor, "cast", spec, 2)
  Combat.emit(w, "cast", actor, "START", record)
  return record
end

-- source: assumed (row C9) the order of the events: SUCCEEDED then STOP for a finished cast, INTERRUPTED then STOP for an
-- interrupted one, FAILED then STOP for a failed one.
function M.finish(w, actor)
  finishWith(w, actor, "cast", { "SUCCEEDED", "STOP" })
end

function M.interrupt(w, actor, byActor)
  finishWith(w, actor, "cast", { "INTERRUPTED", "STOP" }, byActor)
end

function M.fail(w, actor)
  finishWith(w, actor, "cast", { "FAILED", "STOP" })
end

-- spec as for begin. Writes actor.channel and emits CHANNEL_START.
function M.channel(w, actor, spec)
  local record = start(w, actor, "channel", spec, 2)
  Combat.emit(w, "cast", actor, "CHANNEL_START", record)
  return record
end

-- Ends the channel; byActor, when given, is the interrupter the event names.
function M.stopChannel(w, actor, byActor)
  finishWith(w, actor, "channel", { "CHANNEL_STOP" }, byActor)
end

return M
