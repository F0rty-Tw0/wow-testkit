-- Widget state of a Slider, StatusBar and ScrollFrame item in the render snapshot (render_widgets.lua dispatches here).
-- Each field beyond the Phase 2 shape appears only when it differs from the client default. Reads kit state or calls the
-- *.methods bodies directly, never the bound obj:Get*() methods. ctx is { look, frameId } from render_fields.lua.
local M = {}

local BehaviourRange = require("ui.behaviour_range")
local BehaviourScroll = require("ui.behaviour_scroll")
local BehaviourText = require("ui.behaviour_text")
local Read = require("render_read")

local text = BehaviourText.methods

-- The texture fields of the thumb or bar region part, with the size SetSize gave it; nil when there is none.
local function partLook(w, part, ctx)
  if not part then
    return nil
  end
  local state = w.ui.state[part]
  local look = ctx.look(state)
  look.width, look.height = state.width, state.height

  return look
end

function M.slider(w, obj, st, ctx)
  local min, max = text.GetMinMaxValues(w, obj, st)

  return {
    type = "Slider",
    value = text.GetValue(w, obj, st),
    min = min,
    max = max,
    orientation = BehaviourRange.orientation(st, "slider"),
    thumb = partLook(w, BehaviourRange.read(st).thumb, ctx),
  }
end

function M.statusBar(w, obj, st, ctx)
  local min, max = text.GetMinMaxValues(w, obj, st)
  local opts = BehaviourRange.read(st)
  local fillStyle = opts.fillStyle

  return {
    type = "StatusBar",
    value = text.GetValue(w, obj, st),
    min = min,
    max = max,
    color = Read.color({ text.GetStatusBarColor(w, obj, st) }),
    orientation = BehaviourRange.orientation(st, "statusbar"),
    texture = partLook(w, opts.bar, ctx),
    reverse = opts.reverse or nil,
    fillStyle = fillStyle ~= BehaviourRange.DEFAULT_FILL_STYLE and fillStyle or nil,
  }
end

function M.scrollFrame(w, obj, st, ctx)
  local scroll = BehaviourScroll.read(st)
  local methods = BehaviourScroll.methods

  return {
    type = "ScrollFrame",
    child = scroll.child and ctx.frameId(scroll.child) or nil,
    h = scroll.h,
    v = scroll.v,
    hRange = methods.GetHorizontalScrollRange(w, obj, st),
    vRange = methods.GetVerticalScrollRange(w, obj, st),
  }
end

return M
