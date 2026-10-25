-- Session input: click, enter, leave, type and press on a frame named by a snapshot id, a global frame name or a screen
-- point, the way scenario_input.lua drives them. An action the client would ignore replies { ok = false, reason }; a
-- malformed request raises, and Session:call turns that into { ok = false, error }.
local M = {}

local Ids = require("session_ids")
local Input = require("input")
local SessionInputKeys = require("session_input_keys")

local ENGINE = "blizzard"
local DEFAULT_BUTTON = "LeftButton"
local NO_EDIT_FOCUS = "no focused EditBox"

-- The frame a target names, or nil plus the reason there is none. A { x, y } target is the topmost frame under that
-- physical pixel.
local function resolve(w, target)
  if type(target) == "table" then
    local frame = Input.frameAt(w, target.x, target.y)
    return frame, not frame and "nothing at " .. target.x .. ", " .. target.y or nil
  end
  local found = Ids.find(w, target) or rawget(_G, target)
  return found, not found and "unknown target " .. target or nil
end

-- The reason a leave is ignored: the mouse is elsewhere.
local function leaveReason(w, frame)
  if not Input.isFrame(w, frame) then
    return "not a frame"
  end
  return w.input.mouseFocus ~= frame and "does not have the mouse" or nil
end

local function pressReason(w, frame)
  return Input.blockedReason(w, frame, "type") or (w.input.editFocus ~= frame and "does not have focus" or nil)
end

-- source: assumed (P3) a click on an EditBox gives it the keyboard focus, after the click's scripts.
local function clickAndFocus(w, frame, button)
  Input.click(w, frame, button)
  if w.ui.state[frame].plan.isA.editbox then
    frame:SetFocus()
  end
end

local function focusedBox(w)
  local box = w.input.editFocus
  return box, not box and NO_EDIT_FOCUS or nil
end

-- kind -> { reason(w, frame, req) -> reason | nil, act(w, frame, req), untargeted?(w) -> frame | nil, reason? }.
-- untargeted picks the frame of a request without a target; a kind without it needs one.
local KINDS = {
  click = {
    reason = function(w, frame, req)
      return Input.blockedReason(w, frame, "click", req.button or DEFAULT_BUTTON)
    end,
    act = function(w, frame, req)
      w:run(ENGINE, clickAndFocus, w, frame, req.button or DEFAULT_BUTTON)
    end,
  },
  enter = {
    reason = function(w, frame)
      return Input.blockedReason(w, frame, "enter")
    end,
    act = function(w, frame)
      w:run(ENGINE, Input.enter, w, frame)
    end,
  },
  leave = {
    reason = leaveReason,
    act = function(w, frame)
      w:run(ENGINE, Input.leave, w, frame)
    end,
    untargeted = function(w)
      return w.input.mouseFocus
    end,
  },
  type = {
    reason = function(w, frame)
      return Input.blockedReason(w, frame, "type")
    end,
    act = function(w, frame, req)
      w:run(ENGINE, Input.type, w, frame, req.text)
    end,
    untargeted = focusedBox,
  },
  press = {
    reason = pressReason,
    act = function(w, frame, req)
      w:run(ENGINE, Input.press, w, frame, req.key)
    end,
  },
}

local function validateTarget(kind, target)
  if target == nil and kind.untargeted then
    return
  end
  if type(target) == "table" then
    local numbers = type(target.x) == "number" and type(target.y) == "number"
    if not numbers then
      error("input: a point target needs numbers x and y", 0)
    end
    return
  end
  if type(target) ~= "string" then
    error("input: target must be a snapshot id, a frame name or { x, y }", 0)
  end
end

-- Raises on a request that is malformed whatever the world holds.
local function validate(kind, req)
  validateTarget(kind, req.target)
  if req.kind == "type" and type(req.text) ~= "string" then
    error("input: text must be a string for type", 0)
  end
  if req.kind == "press" and type(req.key) ~= "string" then
    error("input: key must be a string for press", 0)
  end
end

-- Runs kind on frame unless the client would ignore it. Returns the reply and whether the world was touched.
local function perform(w, kind, frame, req, reason)
  if frame then
    reason = kind.reason(w, frame, req)
  end
  local target = Ids.target(w, frame)
  if reason then
    return { ok = false, reason = reason, target = target }, false
  end
  kind.act(w, frame, req)

  return { ok = true, target = target }, true
end

-- P1: the cursor moves to the point and the mouse focus to the topmost frame there, leaving the old focus first. A
-- frame whose mouse motion is disabled is not entered; empty space only leaves. Returns the frame (or nil), the
-- reason it was not entered, and whether a script ran.
local function hover(w, point)
  Input.setCursor(w, point.x, point.y)
  local frame = Input.frameAt(w, point.x, point.y)
  local old = w.input.mouseFocus
  if frame == old then
    return frame, nil, false
  end
  local reason = frame and Input.blockedReason(w, frame, "enter")
  if frame and not reason then
    w:run(ENGINE, Input.enter, w, frame)

    return frame, nil, true
  end
  if old then
    w:run(ENGINE, Input.leave, w, old)
  end

  return frame, reason, old ~= nil
end

-- enter and click at a point: P1, then (click, P2) the click on the frame hit; empty space is ok with no target.
local POINTS = {
  enter = function(w, req)
    local frame, reason, moved = hover(w, req.target)
    local reply = { ok = not reason, reason = reason, target = Ids.target(w, frame) }

    return reply, moved
  end,
  click = function(w, req)
    local frame, _, moved = hover(w, req.target)
    if not frame then
      return { ok = true }, moved
    end
    local reply, clicked = perform(w, KINDS.click, frame, req)

    return reply, moved or clicked
  end,
}

-- Runs one input request on sess. Returns the reply and whether the world was touched (the caller bumps seq).
function M.dispatch(sess, req)
  local handler = SessionInputKeys.handlerFor(req)
  if handler then
    return handler(sess, req)
  end
  local kind = KINDS[req.kind]
  if not kind then
    return { ok = false, reason = "unknown input kind " .. tostring(req.kind) }, false
  end
  validate(kind, req)
  local w = sess.w
  local point = type(req.target) == "table" and POINTS[req.kind]
  if point then
    return point(w, req)
  end
  if req.target == nil then
    local frame, reason = kind.untargeted(w)
    if not frame and not reason then
      return { ok = true }, false
    end

    return perform(w, kind, frame, req, reason)
  end

  local frame, reason = resolve(w, req.target)

  return perform(w, kind, frame, req, reason)
end

return M
