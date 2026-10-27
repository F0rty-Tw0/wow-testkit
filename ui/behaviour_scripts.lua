-- Widget script and event methods, delegating to the world's script registry and event bus.
-- Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Callsite = require("ui.callsite")
local Scripts = require("ui.scripts")

local methods = {}
M.methods = methods

-- Errors at the widget method's caller.
local function checkHandler(w, st, script)
  if not Scripts.supports(st.plan.type, script, w.flavor) then
    local message = string.format("%s has no script handler '%s' on %s", st.plan.type, tostring(script), w.flavor)
    error(message, Callsite.level())
  end
end

function methods.SetScript(w, obj, st, script, fn)
  checkHandler(w, st, script)
  w:setScript(obj, script, fn)
end

function methods.HookScript(w, obj, st, script, fn)
  checkHandler(w, st, script)
  w:hookScript(obj, script, fn)
end

function methods.GetScript(w, obj, _, script)
  return w:getScript(obj, script)
end

function methods.HasScript(w, _, st, script)
  return Scripts.supports(st.plan.type, script, w.flavor)
end

-- Events ------------------------------------------------------------------------------------------------------

local FORBIDDEN_EVENTS = { COMBAT_LOG_EVENT = true, COMBAT_LOG_EVENT_UNFILTERED = true }

-- source: confirmed (row C1) on retail 12.0.0 an addon registering the combat log events fires ADDON_ACTION_FORBIDDEN
-- (addon name, function); assumed the call does not raise, registers nothing and the Register call returns false. Blizzard
-- code registers them as before. Follow-up for the taint phase: the "Interface action failed" console line and taint log.
local function forbidden(w, event, call)
  if w.flavor ~= "retail" or not FORBIDDEN_EVENTS[event] or not w:callerIsAddon() then
    return false
  end
  w:run("blizzard", w.fire, w, "ADDON_ACTION_FORBIDDEN", Callsite.addon(w) or "", call .. "()")
  return true
end

-- Tail calls keep an unknown-event error pointing at the caller.
function methods.RegisterEvent(w, obj, _, event)
  if forbidden(w, event, "RegisterEvent") then
    return false
  end
  return w:registerEvent(obj, event)
end

-- source: confirmed (row C15) the frame gets the event only for the listed units (up to four), a repeated call or a later
-- RegisterEvent overwrites the registration, and the call returns registered (true; an unknown event raises in
-- registerEvent); assumed the unit is the event's first argument.
function methods.RegisterUnitEvent(w, obj, _, event, ...)
  if forbidden(w, event, "RegisterUnitEvent") then
    return false
  end
  w:registerEvent(obj, event)
  w:setUnitFilter(obj, event, { ... })
  return true
end

function methods.UnregisterEvent(w, obj, _, event)
  w:unregisterEvent(obj, event)
end

function methods.IsEventRegistered(w, obj, _, event)
  return w:isEventRegistered(obj, event)
end

function methods.UnregisterAllEvents(w, obj)
  for event in pairs(w.eventFrames) do
    w:unregisterEvent(obj, event)
  end
end

return M
