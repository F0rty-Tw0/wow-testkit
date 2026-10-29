-- The pending-timer queue behind w:advance: firing order, cancel in every state, and a NaN delay. Pins the order the
-- queue structure must keep (tests/test_world_timers.lua covers the clock and the loop guard).
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

-- 200 timers with many equal due times; every 7th is cancelled, one of them twice. Fired order is (due, creation).
local function test_many_timers_fire_in_due_order_skipping_cancelled()
  withWorld("retail", function(w)
    local fired, expected, delays, handles = {}, {}, {}, {}
    for i = 1, 200 do
      delays[i] = ((i * 37) % 11) / 4
      handles[i] = _G.C_Timer.NewTimer(delays[i], function()
        fired[#fired + 1] = i
      end)
      if i % 7 ~= 0 then
        expected[#expected + 1] = i
      end
    end
    for i = 7, 200, 7 do
      handles[i]:Cancel()
    end
    handles[7]:Cancel()
    table.sort(expected, function(a, b)
      return delays[a] < delays[b] or (delays[a] == delays[b] and a < b)
    end)
    A.eq(#w.timers, #expected)
    w:advance(10)
    A.same(fired, expected)
    A.eq(#w.timers, 0)
  end)
end

-- Tickers re-queue at their new due time: a (0.5 s) and b (0.75 s) over 3 s, ties by creation.
local function test_tickers_interleave_by_due_time()
  withWorld("retail", function(w)
    local order = {}
    _G.C_Timer.NewTicker(0.5, function()
      order[#order + 1] = "a"
    end)
    _G.C_Timer.NewTicker(0.75, function()
      order[#order + 1] = "b"
    end)
    w:advance(3)
    A.eq(table.concat(order), "abaababaab")
  end)
end

-- A handle cancelled after it fired, twice, or from its own callback removes nobody else's timer.
local function test_cancel_after_fire_twice_or_from_own_callback_keeps_other_timers()
  withWorld("retail", function(w)
    local c, ticks = counter(), 0
    local once = _G.C_Timer.NewTimer(1, c.fn)
    local ticker
    ticker = _G.C_Timer.NewTicker(1, function()
      ticks = ticks + 1
      if ticks == 3 then
        ticker:Cancel()
      end
    end)
    _G.C_Timer.NewTimer(100, c.fn)
    w:advance(5)
    once:Cancel()
    once:Cancel()
    ticker:Cancel()
    A.same({ ticks, c.n, #w.timers }, { 3, 1, 1 })
    w:advance(100)
    A.eq(c.n, 2)
  end)
end

-- A NaN delay is never due: it stays pending and blocks no other timer.
local function test_nan_delay_never_fires_and_blocks_nothing()
  withWorld("retail", function(w)
    local c = counter()
    _G.C_Timer.After(0 / 0, c.fn)
    _G.C_Timer.After(1, c.fn)
    w:advance(5)
    A.eq(c.n, 1)
    A.eq(#w.timers, 1)
  end)
end

return function()
  test_many_timers_fire_in_due_order_skipping_cancelled()
  test_tickers_interleave_by_due_time()
  test_cancel_after_fire_twice_or_from_own_callback_keeps_other_timers()
  test_nan_delay_never_fires_and_blocks_nothing()
end
