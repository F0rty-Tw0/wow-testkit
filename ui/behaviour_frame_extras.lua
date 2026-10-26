-- Frame extras: raise and lower among siblings, the id and the toplevel and fixed level and strata flags, child and region
-- counts, and RegisterAllEvents. Methods are fn(w, obj, st, ...) like ui/behaviour.lua; only frames list these names, so
-- no isA check is needed. The state lives in st.id, st.toplevel, st.fixedLevel and st.fixedStrata.
local M = {}

local BehaviourRender = require("ui.behaviour_render")

local unpack = unpack

local methods = {}
M.methods = methods

local render = BehaviourRender.methods

local ROOT_LEVEL = 0
local DEFAULT_ID = 0

-- The frame levels of obj's siblings in obj's strata; empty without a parent.
local function siblingLevels(w, obj, st)
  local levels = {}
  local parent = st.parent and w.ui.state[st.parent]
  if not parent then
    return levels
  end
  local strata = render.GetFrameStrata(w, obj, st)
  for _, sibling in ipairs(parent.children) do
    local siblingState = w.ui.state[sibling]
    if sibling ~= obj and render.GetFrameStrata(w, sibling, siblingState) == strata then
      levels[#levels + 1] = render.GetFrameLevel(w, sibling, siblingState)
    end
  end

  return levels
end

-- source: row W48 (confirmed above all frames in the strata, assumed the exact levels): one above the highest sibling of
-- the same strata; a frame already above them, or without siblings, keeps its level.
function methods.Raise(w, obj, st)
  local levels = siblingLevels(w, obj, st)
  local level = render.GetFrameLevel(w, obj, st)
  local top = #levels > 0 and math.max(unpack(levels))
  if top and top >= level then
    st.frameLevel = top + 1
  end
end

-- source: row W48 (confirmed below all frames in the strata, assumed the exact levels): one below the lowest sibling of
-- the same strata, not under level 0; a frame already below them, or without siblings, keeps its level.
function methods.Lower(w, obj, st)
  local levels = siblingLevels(w, obj, st)
  local level = render.GetFrameLevel(w, obj, st)
  local bottom = #levels > 0 and math.min(unpack(levels))
  if bottom and bottom <= level then
    st.frameLevel = math.max(ROOT_LEVEL, bottom - 1)
  end
end

-- source: row W51 (confirmed) the default id is 0.
function methods.SetID(_, _, st, id)
  st.id = id
end

function methods.GetID(_, _, st)
  return st.id or DEFAULT_ID
end

-- source: row W49 (confirmed the default false; raise-on-click is not simulated, assumed).
function methods.SetToplevel(_, _, st, toplevel)
  st.toplevel = toplevel and true or false
end

function methods.IsToplevel(_, _, st)
  return st.toplevel == true
end

-- source: row W50 (confirmed the defaults false; re-levelling on SetParent is not simulated, assumed). The api names the
-- getters HasFixedFrameLevel and HasFixedFrameStrata.
function methods.SetFixedFrameLevel(_, _, st, fixed)
  st.fixedLevel = fixed and true or false
end

function methods.HasFixedFrameLevel(_, _, st)
  return st.fixedLevel == true
end

function methods.SetFixedFrameStrata(_, _, st, fixed)
  st.fixedStrata = fixed and true or false
end

function methods.HasFixedFrameStrata(_, _, st)
  return st.fixedStrata == true
end

-- source: row W52 (confirmed) child frames versus non-frame child regions.
function methods.GetNumChildren(_, _, st)
  return #st.children
end

function methods.GetNumRegions(_, _, st)
  return #st.regions
end

-- source: row W54 (confirmed the wiki sentence; assumed that the kit fires all of them): registers the frame for every
-- event of the flavor's manifest, so GetFramesRegisteredForEvent and UnregisterAllEvents see it. Every flavor's Ketho
-- event list (w.globals.events) is a subset of its manifest's, so the manifest alone covers what World:fire accepts.
function methods.RegisterAllEvents(w, obj)
  for event in pairs(w.manifest.events) do
    w:registerEvent(obj, event)
  end
end

return M
