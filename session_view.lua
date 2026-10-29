-- Inspector reads of a world: the widget tree (every frame, texture and font string, hidden and unplaced ones too, in
-- creation order), one widget's properties and the flavor's event list. Like render.lua it reads kit state directly, never an addon-facing
-- method, so no addon code runs and w.unscripted stays as it was (tests/test_session_view.lua pins that).
local M = {}

local Behaviour = require("ui.behaviour")
local BehaviourInput = require("ui.behaviour_input")
local BehaviourRender = require("ui.behaviour_render")
local Finite = require("render_finite")
local Ids = require("session_ids")
local Json = require("json")
local Layout = require("ui.layout")
local Render = require("render")

-- Every widget with a snapshot id as { obj, st, id }, in creation order.
local function widgets(w)
  local list = {}
  for obj, st in pairs(w.ui.state) do
    local id = Ids.of(w, obj)
    if id then
      list[#list + 1] = { obj = obj, st = st, id = id }
    end
  end
  table.sort(list, function(a, b)
    return a.st.seq < b.st.seq
  end)
  return list
end

local function nodeOf(w, widget)
  local st = widget.st
  return {
    id = widget.id,
    name = st.name,
    type = st.plan.type,
    parent = st.parent and Ids.of(w, st.parent),
    shown = st.shown and true or false,
    visible = Behaviour.methods.IsVisible(w, widget.obj, st) and true or false,
  }
end

function M.tree(w)
  local nodes = {}
  for i, widget in ipairs(widgets(w)) do
    nodes[i] = nodeOf(w, widget)
  end
  return { nodes = nodes }
end

-- The ids of the widgets whose parent is obj, in creation order.
local function childrenOf(w, obj)
  local ids = {}
  for _, widget in ipairs(widgets(w)) do
    if widget.st.parent == obj then
      ids[#ids + 1] = widget.id
    end
  end
  return ids
end

-- st.points as wire anchors; relativeTo is an id, or nil for the screen or a target with no id.
local function pointsOf(w, st)
  local points = {}
  for i, anchor in ipairs(st.points) do
    points[i] = { point = anchor[1], relativeTo = Ids.of(w, anchor[2]), relativePoint = anchor[3], x = anchor[4], y = anchor[5] }
  end
  return points
end

-- The names of the scripts that run on obj, sorted: those set on it (a hook alone counts: it becomes the handler) and
-- its type's intrinsic handlers (world_events.lua callScript runs both).
local function scriptsOf(w, obj, st)
  local seen = {}
  for name, entry in pairs(w.scripts[obj] or {}) do
    seen[name] = entry.fn and true or nil
  end
  for _, intrinsic in ipairs({ st.plan.intrinsicScripts or {}, st.plan.intrinsicPostScripts or {} }) do
    for name in pairs(intrinsic) do
      seen[name] = true
    end
  end
  local names = {}
  for name in pairs(seen) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

-- The events obj is registered for, sorted.
local function eventsOf(w, obj)
  local names = {}
  for event, frames in pairs(w.eventFrames) do
    for _, frame in ipairs(frames) do
      if frame == obj then
        names[#names + 1] = event
      end
    end
  end
  table.sort(names)
  return names
end

-- The render snapshot item with the given id, or nil when the widget is not drawn.
local function renderItem(w, id)
  for _, item in ipairs(Render.snapshot(w).items) do
    if item.id == id then
      return item
    end
  end
  return nil
end

-- The properties of the widget id names, or nil for an unknown id. Numbers Json cannot write become Json.null.
function M.frame(w, id)
  local obj = Ids.find(w, id)
  if not obj then
    return nil
  end
  local st = w.ui.state[obj]
  local props = nodeOf(w, { obj = obj, st = st, id = Ids.of(w, obj) })
  props.children = childrenOf(w, obj)
  props.alpha = BehaviourRender.methods.GetAlpha(w, obj, st)
  props.effectiveAlpha = BehaviourRender.methods.GetEffectiveAlpha(w, obj, st)
  props.scale = BehaviourRender.methods.GetScale(w, obj, st)
  props.size = Json.object({ width = st.width, height = st.height })
  props.points = pointsOf(w, st)
  props.rect = Layout.rect(w, obj)
  props.screenRect = Layout.screenRect(w, obj)
  props.mouse = { click = BehaviourInput.methods.IsMouseClickEnabled(w, obj, st), motion = BehaviourInput.methods.IsMouseMotionEnabled(w, obj, st) }
  props.scripts = scriptsOf(w, obj, st)
  props.events = eventsOf(w, obj)
  if st.plan.isFrame then
    props.strata = BehaviourRender.methods.GetFrameStrata(w, obj, st)
    props.level = BehaviourRender.methods.GetFrameLevel(w, obj, st)
  end
  props.render = renderItem(w, props.id)
  return Finite.scrub(props)
end

-- { name, type, nilable } per payload parameter of a manifest event; type is the parameter's Lua type.
local function payloadOf(event)
  local out = {}
  for i, param in ipairs(event.payload or {}) do
    out[i] = { name = param.name, type = param.lua, nilable = param.nilable }
  end
  return out
end

-- Every event of the flavor's API docs as { name, payload }, sorted by name.
function M.events(w)
  local events = w.manifest.events
  local names = {}
  for name in pairs(events) do
    names[#names + 1] = name
  end
  table.sort(names)
  local list = {}
  for i, name in ipairs(names) do
    list[i] = { name = name, payload = payloadOf(events[name]) }
  end
  return list
end

return M
