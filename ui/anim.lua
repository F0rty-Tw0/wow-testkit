-- Animation playback as a pure function of the kit clock: the stored animation values with their defaults, the order
-- timeline of a group and the progress of each animation at a time (the effects on a target are ui/anim_effects.lua).
-- A group's play state lives in its widget state, st.group = { state, startedAt, pausedAt, loops, pendingFinish, timer }
-- (ui/anim_play.lua writes it); nothing here schedules or fires anything. Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local M = {}

local PLAYING, PAUSED, DONE, STOPPED = "PLAYING", "PAUSED", "DONE", "STOPPED"
M.PLAYING, M.PAUSED, M.DONE, M.STOPPED = PLAYING, PAUSED, DONE, STOPPED

-- Each stored setter key (st.values[key] = { n, ... }, written by the generic setters) with the arguments a getter
-- reports and the playback uses before it is set. The getters and the playback both read through M.values, so they
-- agree on every default.
-- source: W57 `order` default 1 (xsd:1583); W58 `looping` default NONE (xsd:1735); W60 `setToFinalAlpha` default false
-- (xsd:1736); W61 `fromAlpha` 0.0 and `toAlpha` 1.0 (xsd:1641-1642); W62 `offsetX` default 0 (xsd:1593); W63 Origin
-- `point` default CENTER (xsd:1553-1557); W64 smoothing default NONE (xsd:1584)
-- source: assumed (the rest): zero duration and delays, scale from and to 1, no rotation, origin offsets 0
local DEFAULTS = {
  Duration = { 0 },
  StartDelay = { 0 },
  EndDelay = { 0 },
  Order = { 1 },
  Smoothing = { "NONE" },
  FromAlpha = { 0 },
  ToAlpha = { 1 },
  Offset = { 0, 0 },
  ScaleFrom = { 1, 1 },
  ScaleTo = { 1, 1 },
  Origin = { "CENTER", 0, 0 },
  Radians = { 0 },
  Looping = { "NONE" },
  ToFinalAlpha = { false },
}

-- Origin point -> { fraction of the width from the left, fraction of the height from the top }.
local PIVOTS = {
  TOPLEFT = { 0, 0 },
  TOP = { 0.5, 0 },
  TOPRIGHT = { 1, 0 },
  LEFT = { 0, 0.5 },
  CENTER = { 0.5, 0.5 },
  RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 1 },
  BOTTOM = { 0.5, 1 },
  BOTTOMRIGHT = { 1, 1 },
}

-- source: assumed (W64) the progress curves; OUT_IN is the alias of IN_OUT (confirmed, wiki API_Animation_SetSmoothing)
local CURVES = {
  NONE = function(p)
    return p
  end,
  IN = function(p)
    return p * p
  end,
  OUT = function(p)
    return 1 - (1 - p) * (1 - p)
  end,
  IN_OUT = function(p)
    return 3 * p * p - 2 * p * p * p
  end,
}
CURVES.OUT_IN = CURVES.IN_OUT

local LOOPINGS = { NONE = true, REPEAT = true, BOUNCE = true }

-- The arguments of the setter key as a list the length of its defaults: a stored one of the right type, else the default.
function M.values(st, key)
  local stored = st.values[key]
  local list = {}
  for i, fallback in ipairs(DEFAULTS[key]) do
    local value = stored and stored[i]
    list[i] = type(value) == type(fallback) and value or fallback
  end

  return list
end

function M.value(st, key)
  return M.values(st, key)[1]
end

local function seconds(st, key)
  return math.max(M.value(st, key), 0)
end

function M.pivot(point)
  return PIVOTS[point] or PIVOTS.CENTER
end

function M.smooth(name, progress)
  local curve = CURVES[name] or CURVES.NONE

  return curve(progress)
end

-- NONE, REPEAT or BOUNCE; anything else plays once.
function M.looping(st)
  local name = M.value(st, "Looping")

  return LOOPINGS[name] and name or "NONE"
end

-- source: assumed (W57) animations of one order play together, order n + 1 starts when all of order n finished, and an
-- order is as long as its longest startDelay + duration + endDelay.
-- { total, items = { { animation, st, at, delay, duration } } }: at is where the animation's order starts.
function M.timeline(w, group)
  local items, lengths, orders = {}, {}, {}
  for _, animation in ipairs(w.ui.state[group].animations or {}) do
    local st = w.ui.state[animation]
    local order = M.value(st, "Order")
    local delay, duration = seconds(st, "StartDelay"), seconds(st, "Duration")
    if lengths[order] == nil then
      lengths[order] = 0
      orders[#orders + 1] = order
    end
    lengths[order] = math.max(lengths[order], delay + duration + seconds(st, "EndDelay"))
    items[#items + 1] = { animation = animation, st = st, order = order, delay = delay, duration = duration }
  end
  table.sort(orders)
  local starts, total = {}, 0
  for _, order in ipairs(orders) do
    starts[order] = total
    total = total + lengths[order]
  end
  for _, item in ipairs(items) do
    item.at = starts[item.order]
  end

  return { total = total, items = items }
end

-- The time inside the timeline at now, and the loop it is in (0 for a single pass). source: assumed (W58) REPEAT
-- restarts and BOUNCE runs every odd pass backwards. A timeline of length 0 plays once.
local function cycle(gs, looping, total, now)
  local elapsed = math.max((gs.pausedAt or now) - gs.startedAt, 0)
  if looping == "NONE" or total <= 0 then
    return elapsed, 0
  end
  local loop = math.max(math.floor(elapsed / total), gs.loops)
  local at = elapsed - loop * total
  if looping == "BOUNCE" and loop % 2 == 1 then
    at = total - at
  end

  return at, loop
end

local function fraction(item, at)
  local into = at - item.at - item.delay
  if item.duration <= 0 then
    return into >= 0 and 1 or 0
  end

  return math.min(math.max(into / item.duration, 0), 1)
end

-- { [animation] = 0..1 } of the timeline's animations at now: the linear progress of each. A group that never played or
-- was stopped has 0 everywhere, a finished one 1 (assumed).
function M.progressOf(w, group, timeline, now)
  local st = w.ui.state[group]
  local gs = st.group
  local at
  if gs and gs.state == DONE then
    at = timeline.total
  elseif gs and (gs.state == PLAYING or gs.state == PAUSED) then
    at = cycle(gs, M.looping(st), timeline.total, now)
  end
  local result = {}
  for _, item in ipairs(timeline.items) do
    result[item.animation] = at and fraction(item, at) or 0
  end

  return result
end

function M.progress(w, group, now)
  return M.progressOf(w, group, M.timeline(w, group), now)
end

-- The target of an animation: its SetTarget widget, else the owner of its group.
function M.target(w, animation)
  local st = w.ui.state[animation]
  local set = st.values.Target and st.values.Target[1]
  if set ~= nil and w.ui.state[set] then
    return set
  end
  local group = w.ui.state[st.parent]

  return group and group.parent
end

return M
