-- Widget script and event methods, delegating to the world's script registry and event bus.
-- Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local Scripts = require("ui.scripts")

local methods = {}
M.methods = methods

-- Errors at the widget method's caller (level 3: this function, the method, its caller).
local function checkHandler(w, st, script)
  if not Scripts.supports(st.plan.scriptType or st.plan.type, script, w.flavor) then
    error(string.format("%s has no script handler '%s' on %s", st.plan.type, tostring(script), w.flavor), 3)
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
  return Scripts.supports(st.plan.scriptType or st.plan.type, script, w.flavor)
end

-- Events ------------------------------------------------------------------------------------------------------

-- Tail calls keep an unknown-event error pointing at the caller.
function methods.RegisterEvent(w, obj, _, event)
  return w:registerEvent(obj, event)
end

-- ponytail: units are not filtered; the frame receives the event for every unit.
function methods.RegisterUnitEvent(w, obj, _, event)
  return w:registerEvent(obj, event)
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
