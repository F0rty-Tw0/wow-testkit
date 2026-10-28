-- Taint log: the demo addon's slash commands fill w.taint.log in the order the client would, the render snapshot carries
-- the log only when it has entries, s:taintLog returns a copy, and the session console gets a line per entry. Lua 5.1 only.
local A = require("assert")
local Combat = require("tests.helpers.combat")
local H = require("tests.helpers.taint")
local HS = require("tests.helpers.session")
local Json = require("json")
local Render = require("render")

local DEMO = { addon = "TaintDemo", root = HS.TAINT }

local function test_demo_slashes_produce_the_expected_log() -- TS8, TS10, TS11
  H.withTaint("retail", function(w, _, s)
    local printed = {}
    w:set("print", function(...)
      local parts = {}
      for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
      end
      printed[#printed + 1] = table.concat(parts, " ")
    end)
    s:login()
    local log = Combat.watch(w, { "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" })
    s:slash("/tdemo cast")
    w:setMock({ combat = true })
    s:slash("/tdemo show")
    w:setMock({ combat = false })
    s:slash("/tdemo taint")
    local kinds = {}
    for i, e in ipairs(s:taintLog()) do
      kinds[i] = e.kind .. ":" .. e.text
    end
    A.same(kinds, {
      "blocked:CastSpellByName() blocked: execution tainted by TaintDemo",
      "blocked:TaintDemoPanel:Show() blocked: execution tainted by TaintDemo", -- prefix per TS10
      "write:global UnitName tainted by TaintDemo",
    })
    A.same({ log[1][1], log[2][1] }, { "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" })
    A.same(printed, {
      "ADDON_ACTION_FORBIDDEN TaintDemo CastSpellByName()",
      "ADDON_ACTION_BLOCKED TaintDemo TaintDemoPanel:Show()",
      "issecurevariable false TaintDemo",
    })
    A.eq(_G.TaintDemoPanel:IsShown(), false)
  end, DEMO)
end

local function test_snapshot_carries_the_log_only_when_it_has_entries()
  H.withTaint("retail", function(w)
    A.eq(Render.snapshot(w).taint, nil)
    H.run(w, "Foo", "return CastSpellByName('Fireball')")
    local snap = Render.snapshot(w)
    A.eq(snap.taint.log[1].kind, "blocked")
    A.eq(snap.taint.log[1].addon, "Foo")
    A.eq(snap.taint.log[1].event, "ADDON_ACTION_FORBIDDEN")
    A.eq(type(Json.encode(snap)), "string")
  end)
end

local function test_snapshot_log_gives_a_table_key_as_text()
  H.withTaint("retail", function(w, Taint)
    Taint.record(w, { kind = "write", addon = "Foo", name = {}, text = "x" })
    local name = Render.snapshot(w).taint.log[1].name
    A.eq(type(name), "string")
    A.eq(type(Json.encode(Render.snapshot(w))), "string")
  end)
end

local function test_scenario_taint_log_returns_a_copy()
  H.withTaint("retail", function(w, _, s)
    H.run(w, "Foo", "return CastSpellByName('Fireball')")
    local copy = s:taintLog()
    A.eq(#copy, 1)
    copy[1].text = "changed"
    copy[2] = { kind = "extra" }
    local again = s:taintLog()
    A.eq(#again, 1)
    A.eq(again[1].text, "CastSpellByName() blocked: execution tainted by Foo")
    A.eq(w.taint.log[1].text, again[1].text)
  end)
end

local function test_console_receives_a_taint_line_per_entry()
  HS.withSession({ addonDir = HS.TAINT }, function(sess)
    sess:call("slash", { text = "/tdemo cast" })
    local taintLines = {}
    for _, line in ipairs(sess:call("console", { since = 0 }).lines) do
      if line.kind == "taint" then
        taintLines[#taintLines + 1] = line.text
      end
    end
    A.same(taintLines, { "taint: CastSpellByName() blocked: execution tainted by TaintDemo" })
  end)
end

local function test_run_and_dump_chunks_run_with_macro_taint_assumed() -- TS2
  HS.withSession({ addonDir = HS.TAINT }, function(sess)
    sess:call("slash", { text = "/run CastSpellByName('Kit Strike'); print('ran', issecure())" })
    sess:call("slash", { text = "/tdemo taint" })
    sess:call("slash", { text = "/run UnitName = UnitName; local s, t = issecurevariable('UnitName'); print('after', s, '[' .. tostring(t) .. ']')" })
    sess:call("slash", { text = "/dump issecure()" })
    local lines = {}
    for _, line in ipairs(sess:call("console", { since = 0 }).lines) do
      if line.kind == "print" or line.kind == "taint" then
        lines[#lines + 1] = line.text
      end
    end
    local blocked = "taint: CastSpellByName() blocked: execution tainted by a macro"
    A.same({ lines[1], lines[3], lines[#lines - 1], lines[#lines] }, { blocked, "ran false", "after false []", "false" })
  end)
end

local function test_session_snapshot_carries_the_taint_log()
  HS.withSession({ addonDir = HS.TAINT }, function(sess)
    A.eq(sess:call("snapshot").taint, nil)
    sess:call("slash", { text = "/tdemo cast" })
    A.eq(sess:call("snapshot").taint.log[1].kind, "blocked")
  end)
end

local function test_destroy_clears_taint_state()
  H.withTaint("retail", function(w)
    H.run(w, "Foo", "return CastSpellByName('Fireball')")
    A.eq(#w.taint.log, 1)
  end)
  H.withTaint("retail", function(w, _, s)
    A.eq(#w.taint.log, 0)
    A.eq(#s:taintLog(), 0)
  end)
end

return function()
  test_demo_slashes_produce_the_expected_log()
  test_snapshot_carries_the_log_only_when_it_has_entries()
  test_snapshot_log_gives_a_table_key_as_text()
  test_scenario_taint_log_returns_a_copy()
  test_console_receives_a_taint_line_per_entry()
  test_run_and_dump_chunks_run_with_macro_taint_assumed()
  test_session_snapshot_carries_the_taint_log()
  test_destroy_clears_taint_state()
end
