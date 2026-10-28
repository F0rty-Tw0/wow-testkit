-- Taint log: the demo addon's slash commands fill w.taint.log in the order the client would, the render snapshot carries
-- the log only when it has entries, s:taintLog returns a copy, and the session console gets a line per entry. Lua 5.1 only.
local A = require("assert")
local Combat = require("tests.helpers.combat")
local H = require("tests.helpers.taint")
local HS = require("tests.helpers.session")

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
  test_scenario_taint_log_returns_a_copy()
  test_destroy_clears_taint_state()
end
