-- Pointer input beyond hover and click: the mouse wheel and the drag. A wheel reaches the topmost visible frame under
-- the point that has the wheel enabled. A drag runs the mouse scripts in the order the tests name. Every rule here is
-- assumed (W1, D1-D6); the tests carry the matching `_assumed` names.
local M = {}

local BehaviourDrag = require("ui.behaviour_drag")
local Input = require("input")
local LayoutHit = require("ui.layout_hit")

local DEFAULT_BUTTON = "LeftButton"
-- source: assumed (D3) a movement of at least this many physical pixels is a drag; less is a click.
local DRAG_PX = 4

-- source: assumed (W1) the frame is found by rect, so it needs no mouse enabled; the topmost wins (LayoutHit.above).
function M.wheel(w, x, y, delta)
  local best
  for frame, st in pairs(w.ui.state) do
    if st.plan.isFrame and st.mouseWheel and frame:IsVisible() and LayoutHit.contains(w, frame, x, y) then
      best = (not best or LayoutHit.above(w, frame, best)) and frame or best
    end
  end
  if best then
    w:callScript(best, "OnMouseWheel", delta)
  end

  return best
end

local function registeredForDrag(w, frame, button)
  for _, registered in ipairs(w.ui.state[frame].dragButtons or {}) do
    if registered == button then
      return true
    end
  end

  return false
end

-- Moves the cursor to the point; a frame being moved or sized follows it.
local function moveCursor(w, point)
  Input.setCursor(w, point.x, point.y)
  BehaviourDrag.follow(w, point.x, point.y)
end

-- source: assumed (D3) OnDragStart(button), the cursor moves to `to`, OnDragStop, OnMouseUp(button, true); no OnClick.
local function dragFrame(w, frame, spec, button)
  w:callScript(frame, "OnDragStart", button)
  moveCursor(w, spec.to)
  w:callScript(frame, "OnDragStop")
  w:callScript(frame, "OnMouseUp", button, true)
end

-- source: assumed (D4) a press and release without a drag: a click when `to` lies inside the same frame, else OnMouseDown
-- then OnMouseUp(button, false) only. The cursor moves to `to` while the button is held either way, so a frame that
-- StartMoving'd in OnMouseDown follows it.
local function releaseFrame(w, frame, spec, button)
  local function move()
    moveCursor(w, spec.to)
  end
  if LayoutHit.contains(w, frame, spec.to.x, spec.to.y) then
    Input.click(w, frame, button, move)

    return
  end
  w:callScript(frame, "OnMouseDown", button)
  move()
  w:callScript(frame, "OnMouseUp", button, false)
end

local function farEnough(spec)
  local dx, dy = spec.to.x - spec.from.x, spec.to.y - spec.from.y

  return dx * dx + dy * dy >= DRAG_PX * DRAG_PX
end

-- source: assumed (D5) carry = true gives the mouse-enabled frame under `to` OnReceiveDrag. It is found before the drag
-- moves anything, so a frame dragged onto `to` does not receive its own drag.
local function receiverOf(w, spec)
  return spec.carry and Input.frameAt(w, spec.to.x, spec.to.y) or nil
end

-- spec = { from = { x, y }, to = { x, y }, button? = "LeftButton", carry? }. Returns { ok, reason?, frame? }: the frame
-- the press hit, or the reason the client would ignore it. A press on empty space is ok with no frame.
function M.drag(w, spec)
  local button = spec.button or DEFAULT_BUTTON
  local frame = Input.frameAt(w, spec.from.x, spec.from.y)
  if not frame then
    return { ok = true }
  end
  local reason = Input.blockedReason(w, frame, "click", button)
  if reason then
    return { ok = false, reason = reason, frame = frame }
  end
  Input.setCursor(w, spec.from.x, spec.from.y)
  local receiver = receiverOf(w, spec)
  if farEnough(spec) and registeredForDrag(w, frame, button) then
    w:callScript(frame, "OnMouseDown", button)
    dragFrame(w, frame, spec, button)
  else
    releaseFrame(w, frame, spec, button)
  end
  if receiver then
    w:callScript(receiver, "OnReceiveDrag")
  end

  return { ok = true, frame = frame }
end

return M
