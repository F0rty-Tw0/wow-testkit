-- Session input that needs no frame target: a key press, keydown and keyup, the mouse wheel at a point, and a drag
-- between two points. session_input.lua hands a request here when handlerFor names one; each handler returns the reply
-- and whether the world was touched, like the kinds there. A malformed request raises, and Session:call turns that into
-- { ok = false, error }.
local M = {}

local Ids = require("session_ids")
local Keys = require("input_keys")
local Pointer = require("input_pointer")

local ENGINE = "blizzard"

local function checkPoint(name, point)
  local numbers = type(point) == "table" and type(point.x) == "number" and type(point.y) == "number"
  if not numbers then
    error("input: " .. name .. " must be { x, y } in screen pixels", 0)
  end
end

local function checkKey(req)
  if type(req.key) ~= "string" then
    error("input: key must be a string for " .. req.kind, 0)
  end
  if req.mods ~= nil and type(req.mods) ~= "table" then
    error("input: mods must be { shift?, ctrl?, alt? }", 0)
  end
end

-- The held state from a state request comes back after the key runs (Keys.holding).
local function holding(w, req, fn)
  return Keys.holding(w, req.mods, w.run, w, ENGINE, fn, w, req.key, req.mods or {})
end

-- The reply of a press, keydown or keyup: the frame that took the key and the command that ran.
local function keyReply(w, result)
  local reply = { ok = true, target = Ids.target(w, result.consumedBy), binding = result.binding }

  return reply
end

local function press(sess, req)
  checkKey(req)
  local w = sess.w
  local result = holding(w, req, Keys.press)

  return keyReply(w, result), true
end

-- source: assumed (K3) a key can go down and come up in separate requests; a key already down ignores a second keydown,
-- and a keyup of a key that is not down does nothing.
local function keydown(sess, req)
  checkKey(req)
  local w = sess.w
  local result = holding(w, req, Keys.down)
  local reply = keyReply(w, result)
  reply.ignored = result.ignored

  return reply, not result.ignored
end

local function keyup(sess, req)
  checkKey(req)
  local w = sess.w
  local held = Keys.isHeld(w, req.key)
  local result = holding(w, req, Keys.up)

  return keyReply(w, result), held
end

local function wheel(sess, req)
  checkPoint("target", req.target)
  if type(req.delta) ~= "number" then
    error("input: delta must be a number for wheel", 0)
  end
  local w = sess.w
  local frame = w:run(ENGINE, Pointer.wheel, w, req.target.x, req.target.y, req.delta)

  return { ok = true, target = Ids.target(w, frame) }, frame ~= nil
end

local function drag(sess, req)
  checkPoint("from", req.from)
  checkPoint("to", req.to)
  if req.button ~= nil and type(req.button) ~= "string" then
    error("input: button must be a string", 0)
  end
  local w = sess.w
  local result = w:run(ENGINE, Pointer.drag, w, req)
  local reply = { ok = result.ok, reason = result.reason, target = Ids.target(w, result.frame) }

  return reply, result.frame ~= nil and result.ok
end

local HANDLERS = { wheel = wheel, drag = drag, keydown = keydown, keyup = keyup }

-- The handler for req, or nil: wheel, drag, keydown, keyup, and a press without a target (a press with one stays in
-- session_input.lua).
function M.handlerFor(req)
  if req.kind == "press" and req.target == nil then
    return press
  end

  return HANDLERS[req.kind]
end

return M
