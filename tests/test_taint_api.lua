-- Secure API answers: issecure, issecurevariable, securecall, securecallfunction, secureexecuterange, forceinsecure,
-- and hooksecurefunc taint. Lua 5.1 only.
local A = require("assert")
local H = require("tests.helpers.taint")

local function test_issecure_follows_the_running_code_assumed() -- TS1
  H.withTaint("retail", function(w)
    A.eq(w:run("blizzard", _G.issecure), true)
    H.run(w, "Foo", "r = issecure()")
    A.eq(_G.r, false)
  end)
end

local function test_issecurevariable_answers_from_the_slots_assumed() -- TS2
  H.withTaint("retail", function(w)
    H.run(
      w,
      "Foo",
      "UnitName = function() end; a, b = issecurevariable('UnitName'); c, d = issecurevariable(_G, 'UnitName'); e, f = issecurevariable('GetTime')"
    )
    A.same({ _G.a, _G.b, _G.c, _G.d, _G.e, _G.f }, { false, "Foo", false, "Foo", true, nil })
  end)
end

local function test_issecurevariable_turns_a_number_key_into_a_string_and_refuses_other_keys_assumed() -- TS2
  H.withTaint("retail", function(w, Taint)
    local t = {}
    w:setGlobal("KitT", t)
    Taint.declare(w, t, "Kit")
    H.run(w, "Foo", "KitT['1'] = true")
    A.same({ _G.issecurevariable(t, 1) }, { false, "Foo" })
    A.errors(function()
      _G.issecurevariable(t, {})
    end, "issecurevariable")
  end)
end

local function test_issecurevariable_answers_for_the_index_table_when_the_field_is_nil_assumed() -- TS2
  H.withTaint("retail", function(w, Taint)
    local base = {}
    w:setGlobal("KitBase", base)
    Taint.declare(w, base, "Kit")
    H.run(w, "Foo", "KitBase.t = 1")
    local child = setmetatable({}, { __index = base })
    A.same({ _G.issecurevariable(child, "t") }, { false, "Foo" })
    A.same({ _G.issecurevariable(child, "other") }, { true, nil })
  end)
end

local function test_securecall_restores_the_callers_taint_assumed() -- TS5
  H.withTaint("retail", function(w, Taint)
    H.probe(w, Taint)
    H.run(w, "Foo", "function FooFn() inner = TK_Seen() end")
    w:run("blizzard", function()
      _G.securecall(_G.FooFn)
      _G.after = Taint.current(w) or "secure"
    end)
    A.same({ _G.inner, _G.after }, { "Foo", "secure" })
  end)
end

local function test_hook_runs_tainted_and_the_original_stays_secure_assumed() -- TS7
  H.withTaint("retail", function(w, Taint)
    H.probe(w, Taint)
    w:setGlobal("TK_Orig", function()
      _G.secureInside = Taint.current(w) or "secure"
    end)
    H.run(w, "Foo", "hooksecurefunc('TK_Orig', function() hookInside = TK_Seen() end)")
    w:run("blizzard", function()
      _G.TK_Orig()
    end)
    A.same({ _G.secureInside, _G.hookInside, (_G.issecurevariable("TK_Orig")) }, { "secure", "Foo", true })
  end)
end

local function test_securecall_from_tainted_code_keeps_the_taint_assumed() -- TS5
  H.withTaint("retail", function(w, Taint)
    H.probe(w, Taint)
    H.run(w, "Foo", "r = securecall(TK_Seen); s = securecallfunction(TK_Seen)")
    A.same({ _G.r, _G.s }, { "Foo", "Foo" })
  end)
end

local function test_securecall_by_name_and_securecallfunction_pass_arguments_and_return_results()
  H.withTaint("retail", function(w)
    w:setGlobal("TK_Add", function(a, b)
      return a + b, "ok"
    end)
    A.same({ _G.securecall("TK_Add", 1, 2) }, { 3, "ok" })
    A.same({ _G.securecallfunction(_G.TK_Add, 3, 4) }, { 7, "ok" })
    A.same({ _G.securecallfunction(function()
      error("boom")
    end) }, {})
    A.eq(#w.errors, 1)
  end)
end

local function test_secureexecuterange_calls_func_with_key_value_and_extras_through_securecall()
  H.withTaint("retail", function(w)
    local seen = {}
    _G.secureexecuterange({ "a", "b" }, function(k, v, extra)
      seen[#seen + 1] = k .. v .. extra
    end, "!")
    A.same(seen, { "1a!", "2b!" })
    seen = {}
    _G.secureexecuterange({ "a", "b" }, function(k, v)
      if k == 1 then
        error("boom")
      end
      seen[#seen + 1] = k .. v
    end)
    A.same(seen, { "2b" })
    A.eq(#w.errors, 1)
  end)
end

local function test_forceinsecure_taints_the_rest_of_the_execution_assumed() -- TS6
  H.withTaint("retail", function(w, Taint)
    A.same({ _G.forceinsecure() }, {})
    A.eq(#H.events(w), 0) -- no frame running
    w:run("blizzard", function()
      _G.forceinsecure()
      A.eq(_G.issecure(), false)
      w:setGlobal("KitX", 1)
    end)
    A.same({ _G.issecurevariable("KitX") }, { false, Taint.FORCED })
    A.eq(Taint.FORCED, "*** ForceTaint_Strong ***")
    A.eq(H.events(w, "forced")[1].text, "execution tainted by forceinsecure")
    A.eq(_G.issecure(), true) -- the frame is gone
  end)
end

local function test_forceinsecure_in_addon_code_keeps_the_addon_taint_assumed() -- TS6
  H.withTaint("retail", function(w)
    H.run(w, "Foo", "forceinsecure(); KitY = 1")
    A.same({ _G.issecurevariable("KitY") }, { false, "Foo" })
    A.eq(#H.events(w, "forced"), 0)
  end)
end

return function()
  test_issecure_follows_the_running_code_assumed()
  test_issecurevariable_answers_from_the_slots_assumed()
  test_issecurevariable_turns_a_number_key_into_a_string_and_refuses_other_keys_assumed()
  test_issecurevariable_answers_for_the_index_table_when_the_field_is_nil_assumed()
  test_securecall_restores_the_callers_taint_assumed()
  test_hook_runs_tainted_and_the_original_stays_secure_assumed()
  test_securecall_from_tainted_code_keeps_the_taint_assumed()
  test_securecall_by_name_and_securecallfunction_pass_arguments_and_return_results()
  test_secureexecuterange_calls_func_with_key_value_and_extras_through_securecall()
  test_forceinsecure_taints_the_rest_of_the_execution_assumed()
  test_forceinsecure_in_addon_code_keeps_the_addon_taint_assumed()
end
