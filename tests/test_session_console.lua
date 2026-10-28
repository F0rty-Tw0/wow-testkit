-- Session console: print and the chat shims feeding one ring of lines, addon errors as error lines, the built-in slash
-- commands (/run, /dump, /advance, unknown ones) and reading the ring since a seq.
local A = require("assert")
local Console = require("session_console")
local H = require("tests.helpers.session")

local function lines(sess)
  return sess:call("console", { since = 0 }).lines
end

local function last(sess)
  local all = lines(sess)
  return all[#all]
end

local function ofKind(sess, kind)
  local out = {}
  for _, line in ipairs(lines(sess)) do
    if line.kind == kind then
      out[#out + 1] = line
    end
  end
  return out
end

local function slash(sess, text)
  return sess:call("slash", { text = text })
end

local function test_print_and_chat_calls_reach_the_console()
  H.withSession(nil, function(sess)
    slash(sess, "/sdemo hi")
    A.same({ last(sess).kind, last(sess).text }, { "print", "slash hi" })
    _G.DEFAULT_CHAT_FRAME:AddMessage("m", 1, 0, 0)
    local chat = last(sess)
    A.same({ chat.kind, chat.text, chat.r, chat.g, chat.b }, { "chat", "m", 1, 0, 0 })
    _G.UIErrorsFrame:AddMessage("e")
    A.same({ last(sess).kind, last(sess).text }, { "error-frame", "e" })
    _G.C_ChatInfo.SendChatMessage("hi", "SAY")
    A.same({ last(sess).kind, last(sess).text }, { "send", "[SAY] hi" })
    _G.SendChatMessage("yo", "YELL")
    A.same({ last(sess).kind, last(sess).text }, { "send", "[YELL] yo" })
    A.same({ sess.w.mock.sent[1].msg, sess.w.mock.sent[2].chatType }, { "hi", "YELL" })
  end)
end

local function test_addon_errors_become_error_lines()
  H.withSession(nil, function(sess)
    slash(sess, "/run print('before')")
    slash(sess, "/sdemo boom")
    local errors = ofKind(sess, "error")
    A.eq(#errors, 1)
    A.contains(errors[1].text, "boom")
    local all = lines(sess)
    A.truthy(#all >= 2)
    for i = 2, #all do
      A.eq(all[i].seq, all[i - 1].seq + 1)
    end
  end)
end

local function test_run_executes_lua_and_reports_errors()
  H.withSession(nil, function(sess)
    A.same(slash(sess, "/run print(1+1)"), { ok = true, handled = true })
    A.same({ last(sess).kind, last(sess).text }, { "print", "2" })
    slash(sess, '/script error("x")')
    A.eq(last(sess).kind, "error")
    A.contains(last(sess).text, "x")
    slash(sess, "/run +")
    A.eq(last(sess).kind, "error")
    A.contains(last(sess).text, "unexpected symbol")
  end)
end

local function test_dump_prints_values()
  H.withSession(nil, function(sess)
    -- Set here so the dump does not depend on what the ADDON_LOADED handler counted.
    slash(sess, "/run SessionDemoDB = { runs = 1 }")
    slash(sess, "/dump SessionDemoDB")
    A.contains(last(sess).text, "runs")
    A.eq(last(sess).text:sub(1, 1), "{")
    slash(sess, "/dump 1+1")
    A.eq(last(sess).text, "2")
    slash(sess, "/dump nope")
    A.eq(last(sess).text, "nil")
  end)
end

local function test_advance_runs_timers()
  H.withSession(nil, function(sess)
    slash(sess, '/run C_Timer.After(0.5, function() print("late") end)')
    A.eq(#ofKind(sess, "print"), 0)
    A.same(slash(sess, "/advance 1"), { ok = true, handled = true })
    A.same({ last(sess).kind, last(sess).text }, { "print", "late" })
    slash(sess, "/advance x")
    A.eq(last(sess).kind, "system")
    A.contains(last(sess).text, "/advance <seconds>")
  end)
end

-- A longer advance runs every per-frame timer it covers in one request, so /advance caps it like combat step.
local function test_advance_rejects_non_finite_and_over_cap()
  H.withSession(nil, function(sess)
    local before = sess.w.now
    for _, arg in ipairs({ "inf", "nan", "1e999", "3601" }) do
      slash(sess, "/advance " .. arg)
      A.same({ last(sess).kind, last(sess).text }, { "system", "Usage: /advance <seconds> (0 to 3600)" })
    end
    A.eq(sess.w.now, before)
    slash(sess, "/advance 3600")
    A.eq(sess.w.now, before + 3600)
  end)
end

local function test_unknown_command_is_a_system_line()
  H.withSession(nil, function(sess)
    A.same(slash(sess, "/nope"), { ok = true, handled = false })
    A.same({ last(sess).kind, last(sess).text }, { "system", "Unknown command: /nope" })
  end)
end

local function test_ring_keeps_the_newest_500()
  H.withSession(nil, function(sess)
    for i = 1, 600 do
      Console.push(sess.w, "system", tostring(i))
    end
    local all = lines(sess)
    A.eq(#all, 500)
    A.eq(all[1].seq, 101)
    A.eq(all[1].text, "101")
    A.eq(all[500].seq, 600)
  end)
end

local function test_console_since_returns_only_new_lines()
  H.withSession(nil, function(sess)
    Console.push(sess.w, "system", "a")
    local since = last(sess).seq
    Console.push(sess.w, "system", "b")
    Console.push(sess.w, "system", "c")
    local fresh = sess:call("console", { since = since }).lines
    A.same({ #fresh, fresh[1].text, fresh[2].text }, { 2, "b", "c" })
    A.eq(#sess:call("console", { since = fresh[2].seq }).lines, 0)
  end)
end

return function()
  test_print_and_chat_calls_reach_the_console()
  test_addon_errors_become_error_lines()
  test_run_executes_lua_and_reports_errors()
  test_dump_prints_values()
  test_advance_runs_timers()
  test_advance_rejects_non_finite_and_over_cap()
  test_unknown_command_is_a_system_line()
  test_ring_keeps_the_newest_500()
  test_console_since_returns_only_new_lines()
end
