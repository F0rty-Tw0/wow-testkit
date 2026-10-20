-- Hand-written widget semantics: anchors, size, visibility, hierarchy, identity, mouse and movement.
-- Each method is fn(w, obj, st, ...) where st is obj's state in w.ui.state. M.methods also carries the text
-- (ui/behaviour_text.lua), alpha/scale/level/strata (ui/behaviour_render.lua) and script/event
-- (ui/behaviour_scripts.lua) methods.
local M = {}

local BehaviourText = require("ui.behaviour_text")
local BehaviourRender = require("ui.behaviour_render")
local BehaviourScripts = require("ui.behaviour_scripts")

local unpack = unpack

local methods = {}
M.methods = methods

local ANCHOR_FIELDS = 5

local function upper(point)
  return type(point) == "string" and point:upper() or point
end

-- A frame name resolves through _G; nil defaults to the parent, else UIParent.
local function relativeOf(st, relativeTo)
  if type(relativeTo) == "string" then
    return _G[relativeTo]
  end
  if relativeTo ~= nil then
    return relativeTo
  end
  return st.parent or _G.UIParent
end

-- The client's SetPoint forms: (point), (point, x, y), (point, relativeTo, x, y),
-- (point, relativeTo, relativePoint [, x, y]). Missing offsets are 0; a missing relativePoint is point.
local function parsePoint(st, point, a, b, c, d)
  point = upper(point)
  if type(a) == "number" then
    return { point, relativeOf(st, nil), point, a, b or 0 }
  end
  if type(b) == "number" then
    return { point, relativeOf(st, a), point, b, c or 0 }
  end
  return { point, relativeOf(st, a), upper(b) or point, c or 0, d or 0 }
end

local function addAnchor(st, anchor)
  for i, existing in ipairs(st.points) do
    if existing[1] == anchor[1] then
      st.points[i] = anchor
      return
    end
  end
  st.points[#st.points + 1] = anchor
end

function methods.SetPoint(_, _, st, ...)
  addAnchor(st, parsePoint(st, ...))
end

function methods.ClearAllPoints(_, _, st)
  st.points = {}
end

function methods.GetPoint(_, _, st, index)
  local anchor = st.points[index or 1]
  if anchor then
    return unpack(anchor, 1, ANCHOR_FIELDS)
  end
end

function methods.GetNumPoints(_, _, st)
  return #st.points
end

function methods.SetAllPoints(_, _, st, relativeTo)
  local target = relativeOf(st, relativeTo)
  st.points = {
    { "TOPLEFT", target, "TOPLEFT", 0, 0 },
    { "BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0 },
  }
end

-- Size --------------------------------------------------------------------------------------------------------

function methods.SetSize(_, _, st, width, height)
  st.width, st.height = width, height
end

function methods.SetWidth(_, _, st, width)
  st.width = width
end

function methods.SetHeight(_, _, st, height)
  st.height = height
end

function methods.GetWidth(_, _, st)
  return st.width or 0
end

function methods.GetHeight(_, _, st)
  return st.height or 0
end

function methods.GetSize(_, _, st)
  return st.width or 0, st.height or 0
end

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

local function setShown(w, obj, st, shown)
  shown = shown and true or false
  if st.shown == shown then
    return
  end
  local wasVisible = isVisible(w, st)
  st.shown = shown
  if isVisible(w, st) ~= wasVisible then
    fireVisibility(w, obj, shown and "OnShow" or "OnHide")
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

-- Moves obj under parent (a widget, a frame name, or nil); parents that are not kit widgets are kept but
-- list nothing.
function M.setParent(w, obj, st, parent)
  if type(parent) == "string" then
    parent = _G[parent]
  end
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

function methods.CreateTexture(w, obj, _, name)
  return w.ui.create("Texture", name, obj)
end

function methods.CreateFontString(w, obj, _, name)
  return w.ui.create("FontString", name, obj)
end

function methods.CreateAnimationGroup(w, obj, _, name)
  return w.ui.create("AnimationGroup", name, obj)
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

-- Mouse and movement ------------------------------------------------------------------------------------------

function methods.EnableMouse(_, _, st, enable)
  st.mouse = enable and true or false
end

function methods.IsMouseEnabled(_, _, st)
  return st.mouse == true
end

function methods.EnableMouseWheel(_, _, st, enable)
  st.mouseWheel = enable and true or false
end

function methods.IsMouseWheelEnabled(_, _, st)
  return st.mouseWheel == true
end

function methods.SetMovable(_, _, st, movable)
  st.movable = movable and true or false
end

function methods.IsMovable(_, _, st)
  return st.movable == true
end

-- No cursor offline: moving is a no-op, but a scripted one (not counted as unscripted).
function methods.StartMoving() end

function methods.StopMovingOrSizing() end

for _, module in ipairs({ BehaviourText, BehaviourRender, BehaviourScripts }) do
  for name, fn in pairs(module.methods) do
    methods[name] = fn
  end
end

return M
