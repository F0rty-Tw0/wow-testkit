-- What playing animations do to a target: the groups that may show (playing and paused ones) and, for one widget, the
-- alpha multiplier, translation, scales and rotation they add up to, and the final alpha a finished group leaves on its
-- targets. Reads w.now and never advances it. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local M = {}

local Anim = require("ui.anim")

-- The groups whose animations may show: playing and paused ones.
function M.activate(w, group)
  local active = w.ui.animActive or {}
  w.ui.animActive = active
  for _, known in ipairs(active) do
    if known == group then
      return
    end
  end
  active[#active + 1] = group
end

function M.deactivate(w, group)
  for i, known in ipairs(w.ui.animActive or {}) do
    if known == group then
      table.remove(w.ui.animActive, i)
      return
    end
  end
end

function M.anyActive(w)
  return w.ui.animActive ~= nil and #w.ui.animActive > 0
end

local function lerp(from, to, progress)
  return from + (to - from) * progress
end

-- source: assumed (W61) Alpha multiplies the target's alpha by from + (to - from) * progress.
local function alpha(fx, st, progress)
  fx.alpha = fx.alpha * lerp(Anim.value(st, "FromAlpha"), Anim.value(st, "ToAlpha"), progress)
end

-- source: assumed (W62) Translation moves the target by offset * progress (y up).
local function translation(fx, st, progress)
  local offset = Anim.values(st, "Offset")
  fx.dx = fx.dx + offset[1] * progress
  fx.dy = fx.dy + offset[2] * progress
end

-- source: assumed (W63) Scale scales about its origin from scaleFrom to scaleTo.
local function scale(fx, st, progress)
  local from, to, origin = Anim.values(st, "ScaleFrom"), Anim.values(st, "ScaleTo"), Anim.values(st, "Origin")
  local entry = { x = lerp(from[1], to[1], progress), y = lerp(from[2], to[2], progress) }
  entry.point, entry.ox, entry.oy = origin[1], origin[2], origin[3]
  fx.scales[#fx.scales + 1] = entry
end

local function rotation(fx, st, progress)
  fx.rotation = fx.rotation + Anim.value(st, "Radians") * progress
end

local CONTRIBUTE = { Alpha = alpha, Translation = translation, Scale = scale, Rotation = rotation }

-- source: W60 Blizzard_ActionBar/Shared/StatusTrackingManager.lua:249 and :262 read GetAlpha after setToFinalAlpha
-- fades (StatusTrackingBar.xml:3, :11, :17), so a finished group that keeps its final alpha sets each target's own
-- alpha; assumed: to the toAlpha of the group's last Alpha animation on that target (highest order, then latest created).
-- The group is done and no longer active (ui/anim_play.lua), so a later SetAlpha or group replaces the alpha.
function M.keepFinalAlpha(w, group)
  local last = {}
  for _, item in ipairs(Anim.timeline(w, group).items) do
    if item.st.plan.type == "Alpha" then
      local target = Anim.target(w, item.animation)
      local isWidget = target ~= nil and w.ui.state[target] ~= nil
      if isWidget and (not last[target] or item.order >= last[target].order) then
        last[target] = item
      end
    end
  end
  for target, item in pairs(last) do
    w.ui.state[target].alpha = Anim.value(item.st, "ToAlpha")
  end
end

-- True when a playing animation of the group targets obj and changed fx.
local function addPlaying(w, group, obj, fx)
  local timeline = Anim.timeline(w, group)
  local linear = Anim.progressOf(w, group, timeline, w.now)
  local hit = false
  for _, item in ipairs(timeline.items) do
    local contribute = CONTRIBUTE[item.st.plan.type]
    if contribute and Anim.target(w, item.animation) == obj then
      contribute(fx, item.st, Anim.smooth(Anim.value(item.st, "Smoothing"), linear[item.animation]))
      hit = true
    end
  end

  return hit
end

-- What the playing animations do to obj itself: nil when none, else { alpha, dx, dy, scales = { { x, y, point, ox,
-- oy } }, rotation }. Reads w.now and never advances it.
function M.effects(w, obj)
  if not M.anyActive(w) then
    return nil
  end
  local fx = { alpha = 1, dx = 0, dy = 0, scales = {}, rotation = 0 }
  local touched = false
  for _, group in ipairs(w.ui.animActive) do
    touched = addPlaying(w, group, obj, fx) or touched
  end

  return touched and fx or nil
end

return M
