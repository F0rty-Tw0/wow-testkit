-- World clock and timers, script registry (shared with widgets), event bus and error recording.
-- Mixed into the World methods by world.lua; state lives on the world and is reset on destroy.
local M = {}

local unpack = unpack

local START_TIME = 1000.0
local ADDON_SOURCE_PATTERN = 'addon:[^:\r\n"%]]+'
local MAX_TIMER_FIRES = 10000

local methods = {}
M.methods = methods

local function pack(...)
  return { n = select("#", ...), ... }
end

-- Passes err to the current error handler under "addon" context. Used as the xpcall message handler, so the
-- handler sees the erroring stack. A failing handler falls back to recordError with both messages.
function methods:reportError(err)
  local stack = self.stack
  local depth = #stack
  stack[depth + 1] = "addon"
  local ok, handlerErr = pcall(self.errorHandler, err)
  stack[depth + 1] = nil
  if not ok then
    self:recordError(tostring(err) .. "\nerror handler failed: " .. tostring(handlerErr), debug.traceback())
  end
end

-- Calls fn(...); an error goes to the error handler. Returns the packed xpcall results ({ n, ok, ... }).
function methods:try(fn, ...)
  local args = pack(...)
  return pack(xpcall(function()
    return fn(unpack(args, 1, args.n))
  end, function(err)
    self:reportError(err)
  end))
end

-- try() under "addon" context.
function methods:callAsAddon(fn, ...)
  local stack = self.stack
  local depth = #stack
  stack[depth + 1] = "addon"
  self:try(fn, ...)
  for i = #stack, depth + 1, -1 do
    stack[i] = nil
  end
end

function M.reset(w)
  w.errorHandler = function(message)
    w:recordError(message, debug.traceback())
  end
  w.now = START_TIME
  w.timers = {}
  w.timerSeq = 0
  w.scripts = setmetatable({}, { __mode = "k" })
  w.eventFrames = {}
end

function methods:recordError(message, traceback)
  local source = tostring(message):match(ADDON_SOURCE_PATTERN)
  if not source and traceback then
    source = tostring(traceback):match(ADDON_SOURCE_PATTERN)
  end
  self.errors[#self.errors + 1] = { message = message, traceback = traceback, source = source }
end

-- Timers ------------------------------------------------------------------------------------------------------

local Timer = {}
Timer.__index = Timer

local function removeTimer(timers, timer)
  for i, t in ipairs(timers) do
    if t == timer then
      table.remove(timers, i)
      return
    end
  end
end

function Timer:Cancel()
  self.cancelled = true
  removeTimer(self.world.timers, self)
end

function Timer:IsCancelled()
  return self.cancelled
end

-- Schedules callback(handle) after seconds; iterations nil repeats forever. Returns the handle.
function methods:schedule(seconds, callback, iterations)
  self.timerSeq = self.timerSeq + 1
  local timer = setmetatable({
    world = self,
    due = self.now + seconds,
    interval = seconds,
    callback = callback,
    remaining = iterations,
    seq = self.timerSeq,
    cancelled = false,
  }, Timer)
  self.timers[#self.timers + 1] = timer
  return timer
end

local function nextDue(timers, limit)
  local best
  for _, t in ipairs(timers) do
    if t.due <= limit and (not best or t.due < best.due or (t.due == best.due and t.seq < best.seq)) then
      best = t
    end
  end
  return best
end

local function fireTimer(w, timer)
  w.now = timer.due
  if timer.remaining then
    timer.remaining = timer.remaining - 1
  end
  if timer.remaining == 0 then
    removeTimer(w.timers, timer)
  else
    timer.due = timer.due + timer.interval
  end
  w:callAsAddon(timer.callback, timer)
end

-- Moves the clock forward, firing due timers in due-time order (ties: creation order) under "addon" context.
-- After MAX_TIMER_FIRES callbacks (e.g. a 0-second ticker) it stops, leaves the clock at the last fired timer
-- and reports a "timer loop" error.
function methods:advance(seconds)
  if type(seconds) ~= "number" or seconds < 0 then
    error("advance: seconds must be a non-negative number, got " .. tostring(seconds), 2)
  end
  local limit = self.now + seconds
  for _ = 1, MAX_TIMER_FIRES do
    local timer = nextDue(self.timers, limit)
    if not timer then
      self.now = limit
      return
    end
    fireTimer(self, timer)
  end
  if not nextDue(self.timers, limit) then
    self.now = limit
    return
  end
  self:reportError(string.format("timer loop: %d timer callbacks in one advance; stopped at %.3f", MAX_TIMER_FIRES, self.now))
end

-- Scripts -----------------------------------------------------------------------------------------------------

local function scriptEntry(w, obj, scriptName)
  local byName = w.scripts[obj]
  if not byName then
    byName = {}
    w.scripts[obj] = byName
  end
  local entry = byName[scriptName]
  if not entry then
    entry = { hooks = {} }
    byName[scriptName] = entry
  end
  return entry
end

function methods:setScript(obj, scriptName, fn)
  scriptEntry(self, obj, scriptName).fn = fn
end

function methods:hookScript(obj, scriptName, fn)
  local hooks = scriptEntry(self, obj, scriptName).hooks
  hooks[#hooks + 1] = fn
end

function methods:getScript(obj, scriptName)
  local byName = self.scripts[obj]
  return byName and byName[scriptName] and byName[scriptName].fn
end

-- Runs the script then its hooks in order, each receiving (obj, ...); errors are recorded, not raised.
function methods:callScript(obj, scriptName, ...)
  local byName = self.scripts[obj]
  local entry = byName and byName[scriptName]
  if not entry then
    return
  end
  if entry.fn then
    self:callAsAddon(entry.fn, obj, ...)
  end
  for _, hook in ipairs(entry.hooks) do
    self:callAsAddon(hook, obj, ...)
  end
end

-- Events ------------------------------------------------------------------------------------------------------

local function checkEvent(w, event)
  if not (w.manifest.events[event] or w.globals.events[event]) then
    error("unknown event '" .. tostring(event) .. "' on " .. w.flavor, 3)
  end
end

local function indexOf(list, item)
  for i, v in ipairs(list) do
    if v == item then
      return i
    end
  end
  return nil
end

function methods:registerEvent(frame, event)
  checkEvent(self, event)
  local frames = self.eventFrames[event] or {}
  self.eventFrames[event] = frames
  if not indexOf(frames, frame) then
    frames[#frames + 1] = frame
  end
end

function methods:unregisterEvent(frame, event)
  local frames = self.eventFrames[event]
  local i = frames and indexOf(frames, frame)
  if i then
    table.remove(frames, i)
  end
end

function methods:isEventRegistered(frame, event)
  local frames = self.eventFrames[event]
  return (frames and indexOf(frames, frame)) ~= nil
end

local function requiredCount(payload)
  for i = #payload, 1, -1 do
    if not payload[i].nilable then
      return i
    end
  end
  return 0
end

-- Warns on too many payload values, or too few: trailing nilable values may be omitted.
local function checkPayload(w, event, count)
  local spec = w.manifest.events[event]
  local payload = spec and spec.payload
  if payload and (count > #payload or count < requiredCount(payload)) then
    local message = "event %s fired with %d payload values; the %s manifest lists %d (%d required)"
    w.warnings[#w.warnings + 1] = string.format(message, event, count, w.flavor, #payload, requiredCount(payload))
  end
end

-- Dispatches OnEvent to frames registered when the fire began; frames unregistered meanwhile are skipped.
function methods:fire(event, ...)
  checkEvent(self, event)
  checkPayload(self, event, select("#", ...))
  local frames = self.eventFrames[event]
  if not frames then
    return
  end
  local snapshot = { unpack(frames) }
  for _, frame in ipairs(snapshot) do
    if indexOf(frames, frame) then
      self:callScript(frame, "OnEvent", event, ...)
    end
  end
end

return M
