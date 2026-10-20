-- WoW Lua extensions installed into every world: string/table/math aliases, hooksecurefunc, securecall,
-- error handler, profiling clock and C_Timer. Clock and timer firing: test_world_timers.lua.
local A = require("assert")
local H = require("tests.helpers.world")

local withWorld = H.withWorld

local function test_strsplit_returns_each_piece()
  withWorld("retail", function()
    A.eq(select("#", _G.strsplit(",", "a,b,c")), 3)
    A.same({ _G.strsplit(",", "a,b,c") }, { "a", "b", "c" })
  end)
end

local function test_strsplit_separator_is_a_set_of_chars()
  withWorld("retail", function()
    A.same({ _G.strsplit(" ,", "a b,c") }, { "a", "b", "c" })
  end)
end

local function test_strsplit_pieces_keeps_rest_in_last()
  withWorld("retail", function()
    A.same({ _G.strsplit(",", "a,b,c", 2) }, { "a", "b,c" })
  end)
end

-- A number argument reads as its string form, as in strtrim (wiki API_strsplit types both as strings).
local function test_strsplit_takes_numbers_as_strings()
  withWorld("retail", function()
    A.same({ _G.strsplit(".", 1.5) }, { "1", "5" })
    A.same({ _G.strsplit(0, "10203") }, { "1", "2", "3" })
  end)
end

local function test_wipe_empties_and_returns_table()
  withWorld("retail", function()
    local t = { 1, 2, x = 3 }
    A.eq(_G.wipe(t), t)
    A.eq(next(t), nil)
  end)
end

local function test_strtrim_and_strjoin()
  withWorld("vanilla", function()
    A.eq(_G.strtrim("  hi \n"), "hi")
    A.eq(_G.strtrim("xxhixx", "x"), "hi")
    A.eq(_G.strjoin("-", "a", "b", "c"), "a-b-c")
  end)
end

-- The doc types both arguments as Lua strings (api/retail/StringUtil.lua string.trim); a C string argument takes a
-- number as its string form (Lua 5.1 manual, lua_tolstring), as validate.lua's ACCEPTS.string does.
local function test_strtrim_takes_numbers_as_strings()
  withWorld("retail", function()
    A.eq(_G.strtrim(5), "5")
    A.eq(H.lookup("string.trim")(5), "5")
    A.eq(_G.strtrim("15051", 1), "505")
  end)
end

local function test_aliases_point_at_host_library()
  withWorld("vanilla", function()
    A.eq(_G.format, string.format)
    A.eq(_G.tinsert, table.insert)
    A.eq(_G.floor, math.floor)
    A.eq(_G.time, os.time)
  end)
end

local function test_unpack_keeps_host_function()
  local hostUnpack = unpack
  withWorld("vanilla", function()
    A.eq(_G.unpack, hostUnpack)
  end)
end

local function test_tcontains()
  withWorld("vanilla", function()
    A.eq(_G.tContains({ "a", "b" }, "b"), true)
    A.eq(_G.tContains({ "a", "b" }, "c"), false)
  end)
end

local function test_hooksecurefunc_table_form_runs_original_then_hook()
  withWorld("retail", function()
    local order, t = {}, {}
    local function original(x)
      order[#order + 1] = "original " .. x
      return x + 10
    end
    t.m = original
    _G.hooksecurefunc(t, "m", function(x)
      order[#order + 1] = "hook " .. x
    end)
    A.eq(t.m(1), 11)
    A.same(order, { "original 1", "hook 1" })
    A.truthy(rawget(t, "m") ~= original)
  end)
end

local function test_hooksecurefunc_global_form_hooks_g()
  withWorld("retail", function(w)
    local seen
    w:setGlobal("TK_Hooked", function(a, b)
      return a .. b
    end)
    _G.hooksecurefunc("TK_Hooked", function(a, b)
      seen = { a, b }
    end)
    A.eq(_G.TK_Hooked("x", "y"), "xy")
    A.same(seen, { "x", "y" })
  end)
end

local function test_hooksecurefunc_hook_runs_in_addon_context()
  withWorld("retail", function(w)
    local t, context = {
      m = function() end,
    }, nil
    _G.hooksecurefunc(t, "m", function()
      context = w:context()
    end)
    w:run("blizzard", t.m)
    A.eq(context, "addon")
  end)
end

local function test_hooksecurefunc_missing_function_errors()
  withWorld("retail", function()
    A.errors(function()
      _G.hooksecurefunc({}, "missing", function() end)
    end, "missing")
  end)
end

local function test_securecall_accepts_function_or_global_name()
  withWorld("retail", function(w)
    w:setGlobal("TK_Add", function(a, b)
      return a + b, "ok"
    end)
    A.same({ _G.securecall(_G.TK_Add, 1, 2) }, { 3, "ok" })
    A.same({ _G.securecall("TK_Add", 2, 2) }, { 4, "ok" })
  end)
end

local function test_issecurevariable_returns_true_nil()
  withWorld("retail", function()
    local secure, taint = _G.issecurevariable({}, "x")
    A.eq(secure, true)
    A.eq(taint, nil)
  end)
end

local function test_default_error_handler_records_error()
  withWorld("retail", function(w)
    _G.geterrorhandler()("boom")
    A.eq(#w.errors, 1)
    A.eq(w.errors[1].message, "boom")
  end)
end

local function test_seterrorhandler_replaces_handler()
  withWorld("retail", function()
    local handler = function() end
    _G.seterrorhandler(handler)
    A.eq(_G.geterrorhandler(), handler)
  end)
end

local function test_seterrorhandler_receives_script_errors_in_addon_context()
  withWorld("retail", function(w)
    local frame, got = {}, nil
    _G.seterrorhandler(function(message)
      got = { message, w:context() }
    end)
    w:setScript(frame, "OnEvent", function()
      error("event failed", 0)
    end)
    w:registerEvent(frame, "PLAYER_LOGIN")
    w:fire("PLAYER_LOGIN")
    A.same(got, { "event failed", "addon" })
    A.eq(#w.errors, 0)
  end)
end

local function test_failing_error_handler_falls_back_to_record_error()
  withWorld("retail", function(w)
    _G.seterrorhandler(function()
      error("handler failed", 0)
    end)
    _G.C_Timer.After(1, function()
      error("timer failed", 0)
    end)
    w:advance(1)
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "timer failed")
    A.contains(w.errors[1].message, "handler failed")
  end)
end

local function test_securecall_reports_error_and_returns_nothing()
  withWorld("retail", function(w)
    local n = select(
      "#",
      _G.securecall(function()
        error("secure failed", 0)
      end)
    )
    A.eq(n, 0)
    A.eq(#w.errors, 1)
    A.eq(w.errors[1].message, "secure failed")
  end)
end

local function test_hooksecurefunc_hook_error_reported_original_results_returned()
  withWorld("retail", function(w)
    local t = {
      m = function()
        return "original"
      end,
    }
    _G.hooksecurefunc(t, "m", function()
      error("hook failed", 0)
    end)
    A.eq(t.m(), "original")
    A.eq(#w.errors, 1)
    A.eq(w.errors[1].message, "hook failed")
  end)
end

local function test_gettime_reads_world_clock()
  withWorld("retail", function(w)
    A.eq(_G.GetTime(), 1000.0)
    w:advance(2.5)
    A.eq(_G.GetTime(), 1002.5)
  end)
end

local function test_debugprofilestop_returns_milliseconds()
  withWorld("retail", function()
    A.eq(type(_G.debugprofilestop()), "number")
  end)
end

local function test_c_timer_counted_and_validated_in_addon_context()
  withWorld("vanilla", function(w)
    w:run("addon", _G.C_Timer.After, 1, function() end)
    A.eq(w.calls["C_Timer.After"], 1)
    A.errors(function()
      w:run("addon", _G.C_Timer.After, 1, nil)
    end, "C_Timer.After")
  end)
end

return function()
  test_strsplit_returns_each_piece()
  test_strsplit_separator_is_a_set_of_chars()
  test_strsplit_pieces_keeps_rest_in_last()
  test_strsplit_takes_numbers_as_strings()
  test_wipe_empties_and_returns_table()
  test_strtrim_and_strjoin()
  test_strtrim_takes_numbers_as_strings()
  test_aliases_point_at_host_library()
  test_unpack_keeps_host_function()
  test_tcontains()
  test_hooksecurefunc_table_form_runs_original_then_hook()
  test_hooksecurefunc_global_form_hooks_g()
  test_hooksecurefunc_hook_runs_in_addon_context()
  test_hooksecurefunc_missing_function_errors()
  test_securecall_accepts_function_or_global_name()
  test_issecurevariable_returns_true_nil()
  test_default_error_handler_records_error()
  test_seterrorhandler_replaces_handler()
  test_seterrorhandler_receives_script_errors_in_addon_context()
  test_failing_error_handler_falls_back_to_record_error()
  test_securecall_reports_error_and_returns_nothing()
  test_hooksecurefunc_hook_error_reported_original_results_returned()
  test_gettime_reads_world_clock()
  test_debugprofilestop_returns_milliseconds()
  test_c_timer_counted_and_validated_in_addon_context()
end
