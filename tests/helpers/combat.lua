-- Combat test helper: a Scenario world with kit-authored spells, the pair of actors most tests use and an event log.
-- Tests never read a client extract or install.
local Actors = require("combat_actors")
local Combat = require("combat")
local Scenario = require("scenario")

local M = {}

M.SPELLS = { STRIKE = 900001, BOLT = 900002, MEND = 900003, WARD = 900004, CURSE = 900005 }

local SPELL_DATA = {
  [M.SPELLS.STRIKE] = { name = "Kit Strike", school = 1 },
  [M.SPELLS.BOLT] = { name = "Kit Bolt", school = 4, castTime = 2000 },
  [M.SPELLS.MEND] = { name = "Kit Mend", school = 2 },
  [M.SPELLS.WARD] = { name = "Kit Ward", harmful = false },
  [M.SPELLS.CURSE] = { name = "Kit Curse", harmful = true },
}

-- Runs fn(w, s) on a fresh Scenario world, always destroyed. The kit's spells are in w.mock.spells; Combat is not
-- installed.
function M.withScenario(flavor, fn)
  local s = Scenario.new({ addon = "T", root = "T", flavor = flavor })
  s.w:setMock({ spells = SPELL_DATA })
  local ok, err = pcall(fn, s.w, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

-- Runs fn(w, c, s) on a fresh Scenario world with Combat installed, always destroyed.
function M.withCombat(flavor, fn)
  M.withScenario(flavor, function(w, s)
    fn(w, Combat.install(w), s)
  end)
end

-- Friendly player Ann (party1, 1000/1000) and hostile npc Brute (boss1, 5000/5000, npcId 4321).
function M.pair(w)
  local ann = Actors.add(w, { kind = "player", name = "Ann", token = "party1", health = 1000, healthMax = 1000 })
  local brute = Actors.add(w, { kind = "npc", name = "Brute", token = "boss1", hostile = true, health = 5000, healthMax = 5000, npcId = 4321 })
  return ann, brute
end

-- A frame registered for events; log[i] = { event, n, ... } in firing order (payload from index 3), also keyed .event and
-- .n.
function M.watch(_, events)
  local log = {}
  local frame = _G.CreateFrame("Frame")
  for _, event in ipairs(events) do
    frame:RegisterEvent(event)
  end
  frame:SetScript("OnEvent", function(_, event, ...)
    local entry = { event, select("#", ...), ... }
    entry.event, entry.n = event, entry[2]
    log[#log + 1] = entry
  end)
  return log
end

-- A frame on COMBAT_LOG_EVENT_UNFILTERED whose handler calls fn(CombatLogGetCurrentEventInfo()). The accessor exists on
-- vanilla, mists and tbc only (row C18), so retail tests read the entry Log.emit returns instead.
function M.onLog(_, fn)
  local frame = _G.CreateFrame("Frame")
  frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  frame:SetScript("OnEvent", function()
    fn(_G.CombatLogGetCurrentEventInfo())
  end)
  return frame
end

-- Subevent names of the combat log entries (c.log.entries), oldest first.
function M.subevents(c)
  local out = {}
  for i, entry in ipairs(c.log.entries) do
    out[i] = entry[2]
  end
  return out
end

-- Firing order of the combat log and the listed unit events: a log entry shows as its subevent. Reads the payload through
-- CombatLogGetCurrentEventInfo, so it needs vanilla, mists or tbc (row C18).
function M.sequence(_, events)
  local out = {}
  local frame = _G.CreateFrame("Frame")
  frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  for _, event in ipairs(events) do
    frame:RegisterEvent(event)
  end
  frame:SetScript("OnEvent", function(_, event)
    out[#out + 1] = event == "COMBAT_LOG_EVENT_UNFILTERED" and select(2, _G.CombatLogGetCurrentEventInfo()) or event
  end)
  return out
end

function M.names(log)
  local out = {}
  for i, entry in ipairs(log) do
    out[i] = entry.event
  end
  return out
end

return M
