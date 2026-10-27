-- Hand-written widget semantics: visibility, hierarchy and identity.
-- Each method is fn(w, obj, st, ...) where st is obj's state in w.ui.state. M.methods also carries the anchor and
-- size (ui/behaviour_layout.lua), text (ui/behaviour_text.lua), texture (ui/behaviour_texture.lua), alpha/scale/level/strata
-- (ui/behaviour_render.lua), region creation (ui/behaviour_regions.lua), script/event (ui/behaviour_scripts.lua),
-- keyboard, wheel, drag, moving and sizing (ui/behaviour_drag.lua), animation (ui/behaviour_animation.lua), attribute
-- (ui/behaviour_attributes.lua), GetDebugName (ui/behaviour_debug_name.lua) and frame extras (ui/behaviour_frame_extras.lua)
-- methods. The button methods (ui/behaviour_button.lua) register through Typed.add into M.typed instead.
local M = {}

local AddonEnv = require("addon_env")
local Callsite = require("ui.callsite")
local BehaviourLayout = require("ui.behaviour_layout")
local BehaviourText = require("ui.behaviour_text")
local BehaviourFontString = require("ui.behaviour_fontstring")
local BehaviourTexture = require("ui.behaviour_texture")
local BehaviourButton = require("ui.behaviour_button")
local BehaviourRender = require("ui.behaviour_render")
local BehaviourRegions = require("ui.behaviour_regions")
local BehaviourScripts = require("ui.behaviour_scripts")
local BehaviourInput = require("ui.behaviour_input")
local BehaviourDrag = require("ui.behaviour_drag")
local BehaviourAnimation = require("ui.behaviour_animation")
local BehaviourAttributes = require("ui.behaviour_attributes")
local BehaviourDebugName = require("ui.behaviour_debug_name")
local BehaviourEdit = require("ui.behaviour_edit")
local BehaviourRange = require("ui.behaviour_range")
local BehaviourScroll = require("ui.behaviour_scroll")
local BehaviourFrameExtras = require("ui.behaviour_frame_extras")

local unpack = unpack

local methods = {}
M.methods = methods
M.typed = BehaviourInput.typed
M.uncheckedArgs = BehaviourAttributes.uncheckedArgs

-- Visibility --------------------------------------------------------------------------------------------------

local function isVisible(w, st)
  while st do
    if not st.shown then
      return false
    end
    st = st.parent and w.ui.state[st.parent]
  end
  return true
end

-- obj's visibility changed: script fires on it and on its shown child frames, whose visibility changed too.
local function fireVisibility(w, obj, script)
  w:callScript(obj, script)
  for _, child in ipairs(w.ui.state[obj].children) do
    if w.ui.state[child].shown then
      fireVisibility(w, child, script)
    end
  end
end

-- source: assumed (K1) hiding the focused EditBox or one of its ancestors clears the focus (OnEditFocusLost), after
-- the OnHide scripts, so an OnHide that calls ClearFocus itself fires it once.
local function dropHiddenFocus(w)
  local box = w.input.editFocus
  if box and not isVisible(w, w.ui.state[box]) then
    BehaviourInput.clearFocus(w, box)
  end
end

local function setShown(w, obj, st, shown)
  shown = shown and true or false
  if st.shown == shown then
    return
  end
  local wasVisible = isVisible(w, st)
  st.shown = shown
  if isVisible(w, st) == wasVisible then
    return
  end
  fireVisibility(w, obj, shown and "OnShow" or "OnHide")
  if not shown then
    dropHiddenFocus(w)
  end
end

methods.SetShown = setShown

function methods.Show(w, obj, st)
  setShown(w, obj, st, true)
end

function methods.Hide(w, obj, st)
  setShown(w, obj, st, false)
end

function methods.IsShown(_, _, st)
  return st.shown
end

function methods.IsVisible(w, _, st)
  return isVisible(w, st)
end

-- Hierarchy ---------------------------------------------------------------------------------------------------

-- The parent's list obj belongs in: frames are children, regions are regions, anything else (animation
-- groups, fonts) is in neither.
local function siblingList(st, parentState)
  if st.plan.isFrame then
    return parentState.children
  elseif st.plan.isA.region then
    return parentState.regions
  end
  return nil
end

local function removeFrom(list, obj)
  for i, item in ipairs(list) do
    if item == obj then
      table.remove(list, i)
      return
    end
  end
end

-- The client refuses a parent that is obj or one of its descendants: "kgPanel16:SetParent(): Would create a loop
-- parenting to kgPanel16" (WoWInterface t-45328, 2012; assumed, no Lua shows it).
local function checkNoLoop(w, obj, st, parent)
  local cursor = parent
  while cursor ~= nil do
    local cursorState = w.ui.state[cursor]
    if cursor == obj then
      local target = w.ui.state[parent]
      local message = "%s:SetParent(): Would create a loop parenting to %s"
      error(string.format(message, st.name or st.plan.type, target.name or target.plan.type), Callsite.level())
    end
    cursor = cursorState and cursorState.parent
  end
end

-- Moves obj under parent (a widget, a frame name, or nil); parents that are not kit widgets are kept but
-- list nothing.
function M.setParent(w, obj, st, parent)
  if type(parent) == "string" then
    parent = AddonEnv.global(w, parent)
  end
  checkNoLoop(w, obj, st, parent)
  local oldState = st.parent and w.ui.state[st.parent]
  local oldList = oldState and siblingList(st, oldState)
  if oldList then
    removeFrom(oldList, obj)
  end
  st.parent = parent
  local newState = parent and w.ui.state[parent]
  local newList = newState and siblingList(st, newState)
  if newList then
    newList[#newList + 1] = obj
  end
end

methods.SetParent = M.setParent

function methods.GetParent(_, _, st)
  return st.parent
end

function methods.GetChildren(_, _, st)
  return unpack(st.children)
end

function methods.GetRegions(_, _, st)
  return unpack(st.regions)
end

-- Identity ----------------------------------------------------------------------------------------------------

function methods.GetName(_, _, st)
  return st.name
end

function methods.GetObjectType(_, _, st)
  return st.plan.type
end

function methods.IsObjectType(_, _, st, typeName)
  return type(typeName) == "string" and st.plan.isA[typeName:lower()] == true
end

-- BehaviourInput goes last: its SetScript wraps BehaviourScripts's.
local MODULES = {
  BehaviourLayout,
  BehaviourText,
  BehaviourFontString,
  BehaviourTexture,
  BehaviourButton,
  BehaviourRender,
  BehaviourRegions,
  BehaviourScripts,
  BehaviourDrag,
  BehaviourAnimation,
  BehaviourAttributes,
  BehaviourDebugName,
  BehaviourInput,
  BehaviourEdit,
  BehaviourRange,
  BehaviourScroll,
  BehaviourFrameExtras,
}
for _, module in ipairs(MODULES) do
  for name, fn in pairs(module.methods) do
    methods[name] = fn
  end
end

return M
