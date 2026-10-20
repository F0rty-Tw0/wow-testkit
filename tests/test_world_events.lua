-- World clock and timers, script registry, event bus, error recording.
local A = require("assert")
local H = require("tests.helpers.world")
local World = require("world")

local withWorld = H.withWorld
-- Retail-only: absent from vanilla's manifest.events and globals.events (checked 2026-10-04).
local RETAIL_ONLY_EVENT = "WEEKLY_REWARDS_UPDATE"
-- Manifest payload: { unitTarget }.
local ONE_ARG_EVENT = "UNIT_HEALTH"
-- Manifest payload: { achievementID, alreadyEarned (nilable) }.
local TRAILING_NILABLE_EVENT = "ACHIEVEMENT_EARNED"

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

local function test_fire_unknown_event_names_event_and_flavor()
  withWorld("vanilla", function(w)
    A.eq(w.manifest.events[RETAIL_ONLY_EVENT], nil)
    A.eq(w.globals.events[RETAIL_ONLY_EVENT], nil)
    local message = A.errors(function()
      w:fire(RETAIL_ONLY_EVENT)
    end, RETAIL_ONLY_EVENT)
    A.contains(message, "vanilla")
  end)
  withWorld("retail", function(w)
    w:fire(RETAIL_ONLY_EVENT)
  end)
end

local function test_register_unknown_event_errors()
  withWorld("vanilla", function(w)
    A.errors(function()
      w:registerEvent({}, RETAIL_ONLY_EVENT)
    end, RETAIL_ONLY_EVENT)
  end)
end

local function test_script_error_recorded_and_dispatch_continues()
  withWorld("retail", function(w)
    local a, b, received = {}, {}, nil
    w:setScript(a, "OnEvent", function()
      error("a failed")
    end)
    w:setScript(b, "OnEvent", function(frame, event)
      received = { frame, event }
    end)
    w:registerEvent(a, "PLAYER_LOGIN")
    w:registerEvent(b, "PLAYER_LOGIN")
    w:fire("PLAYER_LOGIN")
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "a failed")
    A.same(received, { b, "PLAYER_LOGIN" })
  end)
end

local function test_frame_unregistered_during_dispatch_is_skipped()
  withWorld("retail", function(w)
    local a, b, c = {}, {}, counter()
    w:setScript(a, "OnEvent", function()
      w:unregisterEvent(b, "PLAYER_LOGIN")
    end)
    w:setScript(b, "OnEvent", c.fn)
    w:registerEvent(a, "PLAYER_LOGIN")
    w:registerEvent(b, "PLAYER_LOGIN")
    w:fire("PLAYER_LOGIN")
    A.eq(c.n, 0)
    A.eq(w:isEventRegistered(b, "PLAYER_LOGIN"), false)
    A.eq(w:isEventRegistered(a, "PLAYER_LOGIN"), true)
  end)
end

local function test_fire_passes_payload()
  withWorld("retail", function(w)
    local f, got = {}, nil
    w:setScript(f, "OnEvent", function(_, event, unit)
      got = { event, unit }
    end)
    w:registerEvent(f, ONE_ARG_EVENT)
    w:fire(ONE_ARG_EVENT, "player")
    A.same(got, { ONE_ARG_EVENT, "player" })
    A.eq(#w.warnings, 0)
  end)
end

local function test_payload_arity_mismatch_warns()
  withWorld("retail", function(w)
    w:fire(ONE_ARG_EVENT)
    A.eq(#w.warnings, 1)
    A.contains(w.warnings[1], ONE_ARG_EVENT)
  end)
end

local function test_omitted_trailing_nilable_payload_does_not_warn()
  withWorld("retail", function(w)
    w:fire(TRAILING_NILABLE_EVENT, 1)
    w:fire(TRAILING_NILABLE_EVENT, 1, true)
    A.eq(#w.warnings, 0)
    w:fire(TRAILING_NILABLE_EVENT)
    w:fire(TRAILING_NILABLE_EVENT, 1, true, "extra")
    A.eq(#w.warnings, 2)
  end)
end

local function test_call_script_runs_script_then_hooks_in_addon_context()
  withWorld("retail", function(w)
    local obj, order = {}, {}
    local function mark(name)
      return function(self, arg)
        order[#order + 1] = { name, self == obj, arg, w:context() }
      end
    end
    w:hookScript(obj, "OnShow", mark("hook1"))
    w:setScript(obj, "OnShow", mark("script"))
    w:hookScript(obj, "OnShow", mark("hook2"))
    w:callScript(obj, "OnShow", 7)
    A.same(order, {
      { "script", true, 7, "addon" },
      { "hook1", true, 7, "addon" },
      { "hook2", true, 7, "addon" },
    })
  end)
end

local function test_set_script_nil_clears_script_keeps_hooks()
  withWorld("retail", function(w)
    local obj, script, hook = {}, counter(), counter()
    w:setScript(obj, "OnShow", script.fn)
    w:hookScript(obj, "OnShow", hook.fn)
    w:setScript(obj, "OnShow", nil)
    A.eq(w:getScript(obj, "OnShow"), nil)
    w:callScript(obj, "OnShow")
    A.eq(script.n, 0)
    A.eq(hook.n, 1)
  end)
end

local function test_record_error_sets_addon_source()
  withWorld("retail", function(w)
    w:recordError("addon:Foo/Bar.lua:3: attempt to index nil", "stack traceback:")
    A.same(w.errors[1], {
      message = "addon:Foo/Bar.lua:3: attempt to index nil",
      traceback = "stack traceback:",
      source = "addon:Foo/Bar.lua",
    })
  end)
end

local function test_record_error_finds_source_in_traceback()
  withWorld("retail", function(w)
    w:recordError("boom", 'stack traceback:\n\t[string "addon:Foo/Baz.lua"]:9: in function')
    A.eq(w.errors[1].source, "addon:Foo/Baz.lua")
    w:recordError("boom", "stack traceback:\n\tkit.lua:1:")
    A.eq(w.errors[2].source, nil)
  end)
end

local function test_record_error_resolves_truncated_chunk_name_to_registered_one()
  withWorld("retail", function(w)
    w:registerChunk("addon:Foo/Deep/Path/File.lua")
    w:recordError("...p/Path/File.lua:3: boom", "stack traceback:")
    A.eq(w.errors[1].source, "addon:Foo/Deep/Path/File.lua")
  end)
end

local function test_record_error_leaves_ambiguous_truncated_name_unresolved()
  withWorld("retail", function(w)
    w:registerChunk("addon:Foo/A/File.lua")
    w:registerChunk("addon:Bar/A/File.lua")
    w:recordError("...A/File.lua:3: boom", "stack traceback:")
    A.eq(w.errors[1].source, nil)
  end)
end

local function test_call_as_addon_returns_the_packed_results()
  withWorld("retail", function(w)
    local r = w:callAsAddon(function(a, b)
      return a + b, "x"
    end, 1, 2)
    A.same(r, { n = 3, true, 3, "x" })
  end)
end

local function test_call_as_addon_returns_false_for_an_error_and_records_it()
  withWorld("retail", function(w)
    local r = w:callAsAddon(function()
      error("boom")
    end)
    A.eq(r[1], false)
    A.eq(#w.errors, 1)
    A.eq(#w.stack, 0)
  end)
end

local function test_destroy_clears_timers_scripts_and_events()
  local w = World.new({ flavor = "retail" })
  local obj, c = {}, counter()
  _G.C_Timer.After(1, c.fn)
  w:setScript(obj, "OnEvent", c.fn)
  w:registerEvent(obj, "PLAYER_LOGIN")
  w:destroy()
  A.eq(#w.timers, 0)
  A.eq(w:getScript(obj, "OnEvent"), nil)
  A.eq(w:isEventRegistered(obj, "PLAYER_LOGIN"), false)
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
  test_fire_unknown_event_names_event_and_flavor()
  test_register_unknown_event_errors()
  test_script_error_recorded_and_dispatch_continues()
  test_frame_unregistered_during_dispatch_is_skipped()
  test_fire_passes_payload()
  test_payload_arity_mismatch_warns()
  test_omitted_trailing_nilable_payload_does_not_warn()
  test_call_script_runs_script_then_hooks_in_addon_context()
  test_set_script_nil_clears_script_keeps_hooks()
  test_record_error_sets_addon_source()
  test_record_error_finds_source_in_traceback()
  test_record_error_resolves_truncated_chunk_name_to_registered_one()
  test_record_error_leaves_ambiguous_truncated_name_unresolved()
  test_call_as_addon_returns_the_packed_results()
  test_call_as_addon_returns_false_for_an_error_and_records_it()
  test_destroy_clears_timers_scripts_and_events()
end
