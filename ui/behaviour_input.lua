-- Hand-written widget input semantics: mouse state, mouse-over queries, and the SetScript wrapper that applies the
-- mouse-script auto-enable rule. M.methods are fn(w, obj, st, ...) like ui/behaviour.lua; M.typed[name] =
-- function(plan) -> impl | nil picks a type-specific body when the class is built (ui/widgets.lua classFor).
local M = {}

local BehaviourScripts = require("ui.behaviour_scripts")

local methods = {}
M.methods = methods
M.typed = {}

-- Scripts whose assignment implies EnableMouse(true).
local MOUSE_SCRIPTS = { OnEnter = true, OnLeave = true, OnMouseDown = true, OnMouseUp = true }

-- A method body for the types whose plan.isA has the given (lowercase) ancestor, else nil (falls back).
function M.onlyFor(isA, impl)
  return function(plan)
    if plan.isA[isA] then
      return impl
    end
  end
end

-- nil in st.mouseClick / st.mouseMotion means the type default: on for buttons and edit boxes, else off.
local function mouseState(st, key)
  local value = st[key]
  if value == nil then
    return st.plan.isA.button == true or st.plan.isA.editbox == true
  end
  return value
end

function methods.EnableMouse(_, _, st, enable)
  st.mouseClick = enable and true or false
  st.mouseMotion = enable and true or false
end

function methods.SetMouseClickEnabled(_, _, st, enable)
  st.mouseClick = enable and true or false
end

function methods.SetMouseMotionEnabled(_, _, st, enable)
  st.mouseMotion = enable and true or false
end

methods.EnableMouseMotion = methods.SetMouseMotionEnabled

function methods.IsMouseClickEnabled(_, _, st)
  return mouseState(st, "mouseClick")
end

function methods.IsMouseMotionEnabled(_, _, st)
  return mouseState(st, "mouseMotion")
end

function methods.IsMouseEnabled(_, _, st)
  return mouseState(st, "mouseClick") or mouseState(st, "mouseMotion")
end

-- True when obj is the mouse focus or one of its ancestors.
function methods.IsMouseOver(w, obj)
  local frame = w.input.mouseFocus
  while frame do
    if frame == obj then
      return true
    end
    frame = w.ui.state[frame].parent
  end
  return false
end

function methods.IsMouseMotionFocus(w, obj)
  return w.input.mouseFocus == obj
end

-- source: wiki API_ScriptRegion_EnableMouse, "Setting the OnEnter/Leave, OnMouseDown/Up script automatically implies
-- `EnableMouse(true)`" (row I5, user ruling 2026-10-20). OnClick enables nothing; a rejected or cleared script
-- changes nothing.
function methods.SetScript(w, obj, st, script, fn)
  if fn ~= nil and MOUSE_SCRIPTS[script] and BehaviourScripts.methods.HasScript(w, obj, st, script) then
    st.mouseMotion = true
    st.mouseClick = true
  end
  return BehaviourScripts.methods.SetScript(w, obj, st, script, fn)
end

return M
