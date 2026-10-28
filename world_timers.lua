-- Timers on the world clock: schedule, cancel, and advance firing due callbacks under "addon" context.
-- Mixed into the World methods through world_events.lua; the clock and timer list live on the world (w.now,
-- w.timers, w.timerSeq) and are reset there.
local M = {}

-- source: assumed (row BU7): the client runs timers once per frame, so a timer never fires twice in one frame. A frame
-- is 1/60 s, the rate GetFramerate answers (game/session.lua:16, :84).
local FRAME = 1 / 60
local MAX_TIMER_FIRES = 10000

local methods = {}
M.methods = methods

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
-- A negative delay counts as 0, so firing the timer never moves the clock backwards. Scheduled inside a timer callback,
-- the timer is due no earlier than the next frame.
function methods:schedule(seconds, callback, iterations)
  seconds = math.max(seconds, 0)
  self.timerSeq = self.timerSeq + 1
  local timer = setmetatable({
    world = self,
    due = self.now + (self.firingTimer and math.max(seconds, FRAME) or seconds),
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
    timer.due = timer.due + math.max(timer.interval, FRAME)
  end
  local outer = w.firingTimer
  w.firingTimer = true
  w:callAsAddon(timer.callback, timer)
  w.firingTimer = outer
end

-- Moves the clock forward, firing due timers in due-time order (ties: creation order) under "addon" context.
-- After MAX_TIMER_FIRES callbacks within one frame (callbacks that multiply every frame) it stops, leaves the clock at
-- the last fired timer and reports a "timer loop" error.
function methods:advance(seconds)
  if type(seconds) ~= "number" or seconds < 0 then
    error("advance: seconds must be a non-negative number, got " .. tostring(seconds), 2)
  end
  local limit = self.now + seconds
  local frameEnd, fires = -math.huge, 0
  while true do
    local timer = nextDue(self.timers, limit)
    if not timer then
      self.now = limit
      return
    end
    if timer.due >= frameEnd then
      frameEnd, fires = timer.due + FRAME, 0
    end
    if fires == MAX_TIMER_FIRES then
      self:reportError(string.format("timer loop: %d timer callbacks in one frame; stopped at %.3f", fires, self.now))
      return
    end
    fires = fires + 1
    fireTimer(self, timer)
  end
end

return M
