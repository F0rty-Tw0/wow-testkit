-- Keyboard, mouse wheel, drag registration, and moving and sizing a frame with the cursor. Each method is fn(w, obj, st,
-- ...) like ui/behaviour.lua's. w.input.moving = { frame, mode = "move" | "size", point, last = { x, y } | nil } is the
-- move or size in progress; Pointer.drag (input_pointer.lua) feeds it each cursor position through M.follow.
local M = {}

local BehaviourRender = require("ui.behaviour_render")
local Layout = require("ui.layout")

local methods = {}
M.methods = methods

local DEFAULT_SIZING_POINT = "BOTTOMRIGHT"
local MIN_SIZE = 1
-- The edges each sizing point drags.
local EDGES = {
  TOPLEFT = { left = true, top = true },
  TOP = { top = true },
  TOPRIGHT = { right = true, top = true },
  LEFT = { left = true },
  RIGHT = { right = true },
  BOTTOMLEFT = { left = true, bottom = true },
  BOTTOM = { bottom = true },
  BOTTOMRIGHT = { right = true, bottom = true },
}

-- Keyboard and wheel ------------------------------------------------------------------------------------------

-- The generic store keeps only Set*, Get* and Is* names, so these flags are hand-written.
function methods.EnableKeyboard(_, _, st, enable)
  st.keyboard = enable and true or false
end

function methods.IsKeyboardEnabled(_, _, st)
  return st.keyboard == true
end

function methods.EnableMouseWheel(_, _, st, enable)
  st.mouseWheel = enable and true or false
end

function methods.IsMouseWheelEnabled(_, _, st)
  return st.mouseWheel == true
end

-- source: assumed (D3) the buttons are kept as the list in argument order; a call replaces it, none stores {}.
function methods.RegisterForDrag(_, _, st, ...)
  st.dragButtons = { ... }
end

-- Movable and resizable -------------------------------------------------------------------------------------

function methods.SetMovable(_, _, st, movable)
  st.movable = movable and true or false
end

function methods.IsMovable(_, _, st)
  return st.movable == true
end

function methods.SetResizable(_, _, st, resizable)
  st.resizable = resizable and true or false
end

function methods.IsResizable(_, _, st)
  return st.resizable == true
end

-- Moving and sizing -------------------------------------------------------------------------------------------

-- source: assumed (D3) the frame is re-anchored to one BOTTOMLEFT point on UIParent whose offsets are its current left
-- and bottom (clamped, as it draws), keeping its size. Returns false when the frame has no rect.
local function reanchor(w, obj, st)
  local pixel, rect = Layout.pixelRect(w, obj), Layout.rect(w, obj)
  if not (pixel and rect) then
    return false
  end
  local parent = rawget(_G, "UIParent")
  local origin = parent and Layout.pixelRect(w, parent) or { left = 0, bottom = 0 }
  local scale = BehaviourRender.effectiveScale(w, st)
  st.width, st.height = st.width or rect.width, st.height or rect.height
  st.points = { { "BOTTOMLEFT", parent, "BOTTOMLEFT", (pixel.left - origin.left) / scale, (pixel.bottom - origin.bottom) / scale } }
  Layout.invalidate(w, obj)
  return true
end

local function begin(w, obj, st, mode, point)
  if not reanchor(w, obj, st) then
    return
  end
  local cursor = w.input.cursor
  w.input.moving = { frame = obj, mode = mode, point = point, last = cursor and { cursor[1], cursor[2] } or nil }
end

-- source: assumed (D3) StartMoving needs IsMovable().
function methods.StartMoving(w, obj, st)
  if st.movable then
    begin(w, obj, st, "move")
  end
end

-- source: assumed (D3) StartSizing needs IsResizable(); the point defaults to BOTTOMRIGHT and the opposite corner stays.
function methods.StartSizing(w, obj, st, point)
  point = point and point:upper() or DEFAULT_SIZING_POINT
  if st.resizable and EDGES[point] then
    begin(w, obj, st, "size", point)
  end
end

function methods.StopMovingOrSizing(w)
  w.input.moving = nil
end

-- Moves the size by delta (never below MIN_SIZE) and returns the change that applied.
local function grow(st, key, delta)
  local old = st[key]
  st[key] = math.max(MIN_SIZE, old + delta)
  return st[key] - old
end

-- dx grows to the right and dy upwards, in the frame's own units. The corner opposite the point stays where it is: the
-- BOTTOMLEFT offsets follow the left and bottom edges.
local function size(st, point, dx, dy)
  local edges, anchor = EDGES[point], st.points[1]
  if edges.right then
    grow(st, "width", dx)
  elseif edges.left then
    anchor[4] = anchor[4] - grow(st, "width", -dx)
  end
  if edges.top then
    grow(st, "height", dy)
  elseif edges.bottom then
    anchor[5] = anchor[5] - grow(st, "height", -dy)
  end
end

-- The cursor is at the physical pixel x, y (origin top-left): the frame being moved or sized follows the change since
-- the last position, divided by its effective scale.
function M.follow(w, x, y)
  local moving = w.input.moving
  if not moving then
    return
  end
  local last = moving.last
  moving.last = { x, y }
  local st = w.ui.state[moving.frame]
  if not (last and st.points[1]) then
    return
  end
  local scale = BehaviourRender.effectiveScale(w, st)
  local dx, dy = (x - last[1]) / scale, (last[2] - y) / scale
  if moving.mode == "size" then
    size(st, moving.point, dx, dy)
  else
    local anchor = st.points[1]
    anchor[4], anchor[5] = anchor[4] + dx, anchor[5] + dy
  end
  Layout.invalidate(w, moving.frame)
end

return M
