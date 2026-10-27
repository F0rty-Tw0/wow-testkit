-- Combat log text: one readable line per combat log entry (combat_log.lua) for the viewer's log panel, such as
-- "[12.5] Kit Boss: Kit Strike hits Ann for 120". The wording is the kit's own, not the client's combat log strings; the
-- time is seconds since the combat world began (the entry's timestamp less the server time it started from).
local M = {}

local Layout = require("combat_log_layout")

-- Longest first, so a _DOSE suffix is not read as its aura suffix.
local SUFFIXES = {
  "AURA_APPLIED_DOSE",
  "AURA_REMOVED_DOSE",
  "AURA_APPLIED",
  "AURA_REMOVED",
  "AURA_REFRESH",
  "CAST_START",
  "CAST_SUCCESS",
  "CAST_FAILED",
  "INTERRUPT",
  "DISPEL",
  "RESURRECT",
  "ABSORBED",
  "DAMAGE",
  "MISSED",
  "HEAL",
}
local IMPLIED = { DAMAGE_SHIELD = "DAMAGE", DAMAGE_SPLIT = "DAMAGE" }

local function nameOf(name)
  return name or "Unknown"
end

local function amountOf(value)
  return string.format("%d", value or 0)
end

-- The source, then ": <spell>" when the subevent names a spell.
local function actor(f)
  local src = nameOf(f.sourceName)
  return f.spellName and (src .. ": " .. f.spellName) or src
end

local FORMS = {
  DAMAGE = function(f)
    return string.format("%s hits %s for %s", actor(f), nameOf(f.destName), amountOf(f.amount))
  end,
  MISSED = function(f)
    return string.format("%s misses %s (%s)", actor(f), nameOf(f.destName), tostring(f.missType))
  end,
  HEAL = function(f)
    return string.format("%s heals %s for %s", actor(f), nameOf(f.destName), amountOf(f.amount))
  end,
  AURA_APPLIED = function(f)
    local verb = f.auraType == "DEBUFF" and "is afflicted by" or "gains"
    return string.format("%s %s %s", nameOf(f.destName), verb, nameOf(f.spellName))
  end,
  AURA_REMOVED = function(f)
    return string.format("%s fades from %s", nameOf(f.spellName), nameOf(f.destName))
  end,
  AURA_REFRESH = function(f)
    return string.format("%s's %s is refreshed", nameOf(f.destName), nameOf(f.spellName))
  end,
  AURA_APPLIED_DOSE = function(f)
    return string.format("%s gains %s (%s)", nameOf(f.destName), nameOf(f.spellName), amountOf(f.amount))
  end,
  AURA_REMOVED_DOSE = function(f)
    return string.format("%s's %s drops to %s", nameOf(f.destName), nameOf(f.spellName), amountOf(f.amount))
  end,
  CAST_START = function(f)
    return string.format("%s begins casting %s", nameOf(f.sourceName), nameOf(f.spellName))
  end,
  CAST_SUCCESS = function(f)
    local target = f.destName and (" on " .. f.destName) or ""
    return string.format("%s casts %s%s", nameOf(f.sourceName), nameOf(f.spellName), target)
  end,
  CAST_FAILED = function(f)
    return string.format("%s fails to cast %s (%s)", nameOf(f.sourceName), nameOf(f.spellName), tostring(f.failedType))
  end,
  INTERRUPT = function(f)
    return string.format("%s interrupts %s's %s", actor(f), nameOf(f.destName), nameOf(f.extraSpellName))
  end,
  DISPEL = function(f)
    return string.format("%s dispels %s's %s", actor(f), nameOf(f.destName), nameOf(f.extraSpellName))
  end,
  RESURRECT = function(f)
    return string.format("%s resurrects %s", actor(f), nameOf(f.destName))
  end,
  ABSORBED = function(f)
    local shield = nameOf(f.casterName) .. ": " .. nameOf(f.absorbSpellName)
    return string.format("%s absorbs %s for %s", shield, amountOf(f.amount), nameOf(f.destName))
  end,
  UNIT_DIED = function(f)
    return nameOf(f.destName) .. " dies"
  end,
  UNIT_DESTROYED = function(f)
    return nameOf(f.destName) .. " is destroyed"
  end,
  UNIT_DISSIPATES = function(f)
    return nameOf(f.destName) .. " dissipates"
  end,
  PARTY_KILL = function(f)
    return string.format("%s kills %s", nameOf(f.sourceName), nameOf(f.destName))
  end,
}

-- The FORMS key of a subevent: a special's own name (UNIT_DIED), else its suffix; nil when no form reads it.
local function formOf(subevent)
  if FORMS[subevent] then
    return subevent
  elseif IMPLIED[subevent] then
    return IMPLIED[subevent]
  end
  for _, suffix in ipairs(SUFFIXES) do
    if subevent:sub(-#suffix - 1) == "_" .. suffix then
      return suffix
    end
  end
end

-- The entry's values keyed by field name. SPELL_ABSORBED carries the attacking spell only sometimes, so the field
-- count picks the layout.
local function fieldsOf(w, entry)
  local layout = Layout.of(w.flavor)
  local subevent = entry[2]
  local names = Layout.fields(layout, subevent, false)
  if #names ~= entry.n then
    names = Layout.fields(layout, subevent, true)
  end
  local fields = {}
  for i, name in ipairs(names) do
    fields[name] = entry[i]
  end
  return fields
end

-- Seconds since the combat world began at the entry's timestamp.
function M.time(w, entry)
  return entry[1] - w.mock.serverTime
end

-- "[<time>] <text>" for one entry of w's combat log; a subevent with no form reads "<subevent> <source> > <dest>".
function M.line(w, entry)
  local f = fieldsOf(w, entry)
  local form = FORMS[formOf(f.subevent) or ""]
  local text = form and form(f) or string.format("%s %s > %s", f.subevent, nameOf(f.sourceName), nameOf(f.destName))
  return string.format("[%.1f] %s", M.time(w, entry), text)
end

return M
