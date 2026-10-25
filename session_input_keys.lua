-- Session input that needs no frame target: a key press, the mouse wheel at a point, and a drag between two points.
-- session_input.lua hands a request here when handlerFor names one; each handler returns the reply and whether the world
-- was touched, like the kinds there. A malformed request raises, and Session:call turns that into { ok = false, error }.
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

-- source: assumed (K3) the modifiers a press names are the ones held while it runs: IsShiftKeyDown and the others read
-- them in OnKeyDown, OnKeyUp and the binding; the held state from a state request comes back afterwards.
local function pressHolding(w, req)
  local mods = req.mods or {}
  local held = w.mock.modifiers
  w.mock.modifiers = { shift = mods.shift == true, ctrl = mods.ctrl == true, alt = mods.alt == true }
  local ok, result = pcall(w.run, w, ENGINE, Keys.press, w, req.key, mods)
  w.mock.modifiers = held
  if not ok then
    error(result, 0)
  end

  return result
end

local function press(sess, req)
  if type(req.key) ~= "string" then
    error("input: key must be a string for press", 0)
  end
  if req.mods ~= nil and type(req.mods) ~= "table" then
    error("input: mods must be { shift?, ctrl?, alt? }", 0)
  end
  local w = sess.w
  local result = pressHolding(w, req)

  return { ok = true, target = Ids.target(w, result.consumedBy), binding = result.binding }, true
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

local HANDLERS = { wheel = wheel, drag = drag }

-- The handler for req, or nil: wheel, drag, and a press without a target (a press with one stays in session_input.lua).
function M.handlerFor(req)
  if req.kind == "press" and req.target == nil then
    return press
  end

  return HANDLERS[req.kind]
end

return M
