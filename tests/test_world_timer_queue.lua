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

-- Small LCG (Numerical Recipes constants, mod 2^32): fixed sequence, no math.random state shared with other tests.
local function lcg(seed)
  local state = seed
  return function(n)
    state = (state * 1664525 + 1013904223) % 4294967296
    return math.floor(state / 65536) % n + 1
  end
end

-- 300 random schedule/cancel rounds on one world; cancelling from the middle of the heap moves its last timer into the
-- hole, and only a sift up (not just down) keeps the order when that timer is due earlier than the hole's new parent.
-- Survivors must fire by (due, creation).
local function test_random_cancels_from_the_middle_keep_due_order()
  withWorld("retail", function(w)
    local random, bad = lcg(13), {}
    for trial = 1, 300 do
      local fired, delays, handles, alive = {}, {}, {}, {}
      local n = random(36) + 4
      for i = 1, n do
        delays[i] = random(50) / 10
        handles[i] = _G.C_Timer.NewTimer(delays[i], function()
          fired[#fired + 1] = i
        end)
        alive[i] = true
      end
      for _ = 1, random(n) do
        local i = random(n)
        handles[i]:Cancel()
        alive[i] = false
      end
      local expected = {}
      for i = 1, n do
        if alive[i] then
          expected[#expected + 1] = i
        end
      end
      table.sort(expected, function(a, b)
        return delays[a] < delays[b] or (delays[a] == delays[b] and a < b)
      end)
      w:advance(10)
      if table.concat(fired, ",") ~= table.concat(expected, ",") then
        bad[#bad + 1] = trial
      end
    end
    A.same(bad, {})
    A.eq(#w.timers, 0)
  end)
end

-- The heap index is private to the kit: an addon writing .slot on the handle it was given cannot misplace the timer.
local function test_addon_written_slot_field_does_not_break_cancel()
  withWorld("retail", function(w)
    local n = 0
    _G.C_Timer.NewTicker(0.5, counter().fn)
    local ticker = _G.C_Timer.NewTicker(1, function()
      n = n + 1
    end)
    w:advance(2.1)
    ticker.slot = 7
    ticker:Cancel()
    w:advance(5)
    A.same({ n, ticker:IsCancelled(), #w.timers }, { 2, true, 1 })
  end)
end

return function()
  test_many_timers_fire_in_due_order_skipping_cancelled()
  test_tickers_interleave_by_due_time()
  test_cancel_after_fire_twice_or_from_own_callback_keeps_other_timers()
  test_nan_delay_never_fires_and_blocks_nothing()
  test_random_cancels_from_the_middle_keep_due_order()
  test_addon_written_slot_field_does_not_break_cancel()
end
