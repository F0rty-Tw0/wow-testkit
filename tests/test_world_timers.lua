-- World clock and timers: C_Timer.After, NewTicker, NewTimer and advance.
-- A per-frame timer started at 1000 over advance(1): frames 0/60 .. 60/60, both ends included.
local ZERO_TICKER_FIRES = 61

local A = require("assert")
local H = require("tests.helpers.world")

local withWorld = H.withWorld

local function counter()
  local c = { n = 0 }
  function c.fn()
    c.n = c.n + 1
  end
  return c
end

local function test_after_fires_once_when_due()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.After(5, c.fn)
    w:advance(4)
    A.eq(c.n, 0)
    A.eq(_G.GetTime(), 1004)
    w:advance(1)
    A.eq(c.n, 1)
    A.eq(_G.GetTime(), 1005)
    w:advance(10)
    A.eq(c.n, 1)
  end)
end

local function test_ticker_fires_its_iterations()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.NewTicker(1, c.fn, 3)
    w:advance(10)
    A.eq(c.n, 3)
  end)
end

local function test_ticker_cancel_stops_it()
  withWorld("retail", function(w)
    local c = counter()
    local ticker = _G.C_Timer.NewTicker(1, c.fn)
    w:advance(2)
    ticker:Cancel()
    w:advance(5)
    A.eq(c.n, 2)
    A.eq(ticker:IsCancelled(), true)
  end)
end

local function test_new_timer_passes_handle_and_can_be_cancelled()
  withWorld("retail", function(w)
    local got
    local timer = _G.C_Timer.NewTimer(1, function(handle)
      got = handle
    end)
    A.eq(timer:IsCancelled(), false)
    w:advance(1)
    A.eq(got, timer)
    local c = counter()
    _G.C_Timer.NewTimer(1, c.fn):Cancel()
    w:advance(1)
    A.eq(c.n, 0)
  end)
end

local function test_timers_fire_in_due_order_ties_by_creation()
  withWorld("retail", function(w)
    local order = {}
    local function mark(name)
      return function()
        order[#order + 1] = name .. "@" .. _G.GetTime()
      end
    end
    _G.C_Timer.After(2, mark("late"))
    _G.C_Timer.After(1, mark("first"))
    _G.C_Timer.After(1, mark("second"))
    w:advance(3)
    A.same(order, { "first@1001", "second@1001", "late@1002" })
  end)
end

local function test_timer_scheduled_during_advance_within_window_fires()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.After(1, function()
      _G.C_Timer.After(1, c.fn)
      _G.C_Timer.After(5, c.fn)
    end)
    w:advance(3)
    A.eq(c.n, 1)
  end)
end

local function test_timer_callback_runs_in_addon_context()
  withWorld("retail", function(w)
    local context
    _G.C_Timer.After(1, function()
      context = w:context()
    end)
    w:advance(1)
    A.eq(context, "addon")
  end)
end

local function test_advance_rejects_negative_seconds()
  withWorld("retail", function(w)
    A.errors(function()
      w:advance(-1)
    end, "advance")
  end)
end

local function test_advance_rejects_non_finite_seconds()
  withWorld("retail", function(w)
    local before = w.now
    A.errors(function()
      w:advance(math.huge)
    end, "advance")
    A.errors(function()
      w:advance(0 / 0)
    end, "advance")
    A.eq(w.now, before)
  end)
end

local function test_negative_delay_fires_now_without_moving_clock_back()
  withWorld("retail", function(w)
    local seen
    _G.C_Timer.After(-5, function()
      seen = _G.GetTime()
    end)
    w:advance(0)
    A.eq(seen, 1000)
    A.eq(_G.GetTime(), 1000)
  end)
end

-- A frame is 1/60 s (GetFramerate's 60): the ticker fires at 1000, 1000 + 1/60, ... while its due stays within 1001.
local function test_zero_interval_ticker_fires_once_per_frame_assumed()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.NewTicker(0, c.fn)
    w:advance(1)
    A.eq(c.n, ZERO_TICKER_FIRES)
    A.eq(#w.errors, 0)
  end)
end

local function test_short_interval_ticker_fires_at_most_once_per_frame_assumed()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.NewTicker(0.001, c.fn)
    w:advance(1)
    A.eq(c.n, 60)
  end)
end

local function test_ticker_longer_than_a_frame_keeps_its_interval()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.NewTicker(0.5, c.fn)
    w:advance(1)
    A.eq(c.n, 2)
  end)
end

local function test_top_level_after_zero_fires_on_advance_zero()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.After(0, c.fn)
    w:advance(0)
    A.eq(c.n, 1)
  end)
end

-- A timer scheduled inside a callback for less than a frame is due on the next frame, never the one running.
local function test_after_zero_from_a_callback_waits_a_frame_assumed()
  withWorld("retail", function(w)
    local c = counter()
    local function again()
      c.fn()
      _G.C_Timer.After(0, again)
    end
    _G.C_Timer.After(0, again)
    w:advance(0)
    A.eq(c.n, 1)
    A.eq(_G.GetTime(), 1000)
    w:advance(1)
    A.eq(c.n, ZERO_TICKER_FIRES)
    A.eq(#w.errors, 0)
  end)
end

-- The guard counts callbacks in one frame, so a long advance over a per-frame ticker is no loop.
local function test_long_advance_over_zero_interval_ticker_is_not_a_loop_assumed()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.NewTicker(0, c.fn)
    w:advance(200)
    A.truthy(c.n > 10000, "fires: " .. c.n)
    A.eq(#w.errors, 0)
  end)
end

-- Each callback schedules two more for the next frame: frames 0-13 fire 2^14 - 1 callbacks, and frame 14 stops at 10000.
local function test_callbacks_doubling_every_frame_hit_loop_guard()
  withWorld("retail", function(w)
    local c = counter()
    local function fork()
      c.fn()
      _G.C_Timer.After(0, fork)
      _G.C_Timer.After(0, fork)
    end
    _G.C_Timer.After(0, fork)
    w:advance(1)
    A.eq(c.n, 16383 + 10000)
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "timer loop")
  end)
end

return function()
  test_after_fires_once_when_due()
  test_ticker_fires_its_iterations()
  test_ticker_cancel_stops_it()
  test_new_timer_passes_handle_and_can_be_cancelled()
  test_timers_fire_in_due_order_ties_by_creation()
  test_timer_scheduled_during_advance_within_window_fires()
  test_timer_callback_runs_in_addon_context()
  test_advance_rejects_negative_seconds()
  test_advance_rejects_non_finite_seconds()
  test_negative_delay_fires_now_without_moving_clock_back()
  test_zero_interval_ticker_fires_once_per_frame_assumed()
  test_short_interval_ticker_fires_at_most_once_per_frame_assumed()
  test_ticker_longer_than_a_frame_keeps_its_interval()
  test_top_level_after_zero_fires_on_advance_zero()
  test_after_zero_from_a_callback_waits_a_frame_assumed()
  test_long_advance_over_zero_interval_ticker_is_not_a_loop_assumed()
  test_callbacks_doubling_every_frame_hit_loop_guard()
end
