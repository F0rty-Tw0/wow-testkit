-- Session input: click, enter, leave, type and press on a frame named by a snapshot id, a global frame name or a screen
-- point, the way scenario_input.lua drives them. An action the client would ignore replies { ok = false, reason }; a
-- malformed request raises, and Session:call turns that into { ok = false, error }.
local M = {}

local Ids = require("session_ids")
local Input = require("input")

local ENGINE = "blizzard"
local DEFAULT_BUTTON = "LeftButton"

-- The frame a target names, or nil plus the reason there is none. A { x, y } target is the topmost frame under that
-- physical pixel.
local function resolve(w, target)
  if type(target) == "table" then
    if type(target.x) ~= "number" or type(target.y) ~= "number" then
      error("input: a point target needs numbers x and y", 0)
    end
    local frame = Input.frameAt(w, target.x, target.y)
    return frame, not frame and "nothing at " .. target.x .. ", " .. target.y or nil
  end
  local found = Ids.find(w, target) or rawget(_G, target)
  return found, not found and "unknown target " .. target or nil
end

local function targetOf(w, frame)
  local id = Ids.of(w, frame)
  return id and { id = id, name = w.ui.state[frame].name } or nil
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

-- kind -> { reason(w, frame, req) -> reason | nil, act(w, frame, req) }
local KINDS = {
  click = {
    reason = function(w, frame, req)
      return Input.blockedReason(w, frame, "click", req.button or DEFAULT_BUTTON)
    end,
    act = function(w, frame, req)
      w:run(ENGINE, Input.click, w, frame, req.button or DEFAULT_BUTTON)
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
  },
  type = {
    reason = function(w, frame)
      return Input.blockedReason(w, frame, "type")
    end,
    act = function(w, frame, req)
      w:run(ENGINE, Input.type, w, frame, req.text)
    end,
  },
  press = {
    reason = pressReason,
    act = function(w, frame, req)
      w:run(ENGINE, Input.press, w, frame, req.key)
    end,
  },
}

-- Raises on a request that is malformed whatever the world holds.
local function validate(req)
  local target = req.target
  if type(target) ~= "string" and type(target) ~= "table" then
    error("input: target must be a snapshot id, a frame name or { x, y }", 0)
  end
  if req.kind == "type" and type(req.text) ~= "string" then
    error("input: text must be a string for type", 0)
  end
  if req.kind == "press" and type(req.key) ~= "string" then
    error("input: key must be a string for press", 0)
  end
end

-- Runs one input request on sess. Returns the reply and whether the world was touched (the caller bumps seq).
function M.dispatch(sess, req)
  local kind = KINDS[req.kind]
  if not kind then
    return { ok = false, reason = "unknown input kind " .. tostring(req.kind) }, false
  end
  validate(req)
  local w = sess.w
  local frame, reason = resolve(w, req.target)
  if frame then
    reason = kind.reason(w, frame, req)
  end
  local target = frame and targetOf(w, frame)
  if reason then
    return { ok = false, reason = reason, target = target }, false
  end
  kind.act(w, frame, req)
  return { ok = true, target = target }, true
end

return M
