-- World clock and timers: C_Timer.After, NewTicker, NewTimer and advance.
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

local function test_zero_interval_ticker_hits_loop_guard()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.NewTicker(0, c.fn)
    w:advance(1)
    A.eq(c.n, 10000)
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
  test_negative_delay_fires_now_without_moving_clock_back()
  test_zero_interval_ticker_hits_loop_guard()
end
