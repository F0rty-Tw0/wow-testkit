-- Addon sandbox: host-only globals stay out of addon code, and an addon that sets debug, io or os breaks no later
-- addon or kit feature.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local Golden = require("golden")
local H = require("tests.helpers.world")
local fs = require("fs")

local withWorld = H.withWorld

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local ADDONS_DIR = TEST_DIR .. "/fixtures/addons"

local function load(w, name)
  return Addon.load(w, { name = name, root = ADDONS_DIR .. "/" .. name })
end

local function errorMessages(w)
  local messages = {}
  for i, entry in ipairs(w.errors) do
    messages[i] = tostring(entry.message)
  end
  return table.concat(messages, "\n")
end

local function test_addon_code_cannot_reach_host_only_globals()
  withWorld("retail", function(w)
    local ns = load(w, "Sandbox")
    A.same(w.errors, {})
    local seen = ns.seen
    A.same(seen, {
      gRequire = "nil",
      io = "nil",
      package = "nil",
      loadfile = "nil",
      dofile = "nil",
      debug = "nil",
      gIo = "nil",
      gG = true,
    })
  end)
end

local function test_addon_os_keeps_only_the_time_functions()
  withWorld("retail", function(w)
    local ns = load(w, "Sandbox")
    A.eq(ns.osTime, "number")
    A.eq(ns.osExecute, "nil")
  end)
end

local function test_addon_getfenv_and_loadstring_do_not_reach_the_real_globals()
  withWorld("retail", function(w)
    local ns = load(w, "Sandbox")
    A.eq(ns.loadstring, "function")
    A.eq(ns.getfenv, "function")
    A.eq(ns.fenvRequire, "nil")
    A.eq(ns.loadstringRequire, "nil")
    A.eq(ns.loadstringIo, "nil")
  end)
end

local function test_addon_rawget_and_pairs_on_g_see_globals_but_not_host_only_names()
  withWorld("retail", function(w)
    local ns = load(w, "Sandbox")
    A.eq(ns.rawRequire, "nil")
    A.eq(ns.pairsIo, false)
    A.eq(ns.pairsFoo, true)
  end)
end

local function test_addon_write_through_g_is_a_global_removed_on_destroy()
  withWorld("retail", function(w)
    local ns = load(w, "Sandbox")
    A.eq(rawget(_G, "SandboxFoo"), 1)
    A.eq(ns.rawFoo, 1)
  end)
  A.eq(rawget(_G, "SandboxFoo"), nil)
end

-- Writes a one-file retail addon named name whose Core.lua is source; returns its root.
local function tempAddon(name, source)
  local root = Tmp.dir("addon") .. "/" .. name
  fs.mkdirp(root)
  fs.writeFile(root .. "/" .. name .. ".toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", source)
  return root
end

local function test_addon_errors_are_still_recorded_after_an_addon_sets_debug()
  withWorld("retail", function(w)
    Addon.load(w, { name = "DebugSet", root = tempAddon("DebugSet", "debug = true\n") })
    Addon.load(w, { name = "DebugBoom", root = tempAddon("DebugBoom", 'error("boom")\n') })
    A.eq(errorMessages(w), "addon:DebugBoom/Core.lua:1: boom")
  end)
end

local FAILING_HANDLER = 'debug = true\nseterrorhandler(function() error("handler broke") end)\n'

local function test_a_failing_error_handler_still_records_after_an_addon_sets_debug()
  withWorld("retail", function(w)
    Addon.load(w, { name = "DebugHandler", root = tempAddon("DebugHandler", FAILING_HANDLER) })
    Addon.load(w, { name = "DebugBoom2", root = tempAddon("DebugBoom2", 'error("boom2")\n') })
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "addon:DebugBoom2/Core.lua:1: boom2")
    A.contains(w.errors[1].message, "handler broke")
  end)
end

local function test_later_addons_still_load_after_an_addon_sets_io()
  local setRoot, nextRoot = tempAddon("IoSet", "io = 1\n"), tempAddon("IoNext", "local _, ns = ...\nns.loaded = true\n")
  withWorld("retail", function(w)
    Addon.load(w, { name = "IoSet", root = setRoot })
    local ns = Addon.load(w, { name = "IoNext", root = nextRoot })
    A.same({ errorMessages(w), ns.loaded }, { "", true })
  end)
end

local function test_a_golden_update_still_writes_after_an_addon_sets_io()
  local setRoot, goldenRoot = tempAddon("IoGolden", "io = 1\n"), Tmp.dir("addon")
  withWorld("retail", function(w)
    Addon.load(w, { name = "IoGolden", root = setRoot })
    A.eq(Golden.check(goldenRoot, "scn", "snap", "retail", "hello\n", true), "written")
  end)
  A.eq(fs.readFile(goldenRoot .. "/tests/scenarios/golden/scn/snap.retail.txt"), "hello\n")
end

local function test_debugprofilestop_still_works_after_an_addon_clears_os()
  local clearRoot = tempAddon("OsClear", "os = nil\n")
  local useRoot = tempAddon("OsUse", "local _, ns = ...\nns.ms = debugprofilestop()\n")
  withWorld("retail", function(w)
    Addon.load(w, { name = "OsClear", root = clearRoot })
    local ns = Addon.load(w, { name = "OsUse", root = useRoot })
    A.same({ errorMessages(w), type(ns.ms) }, { "", "number" })
  end)
end

return function()
  test_addon_code_cannot_reach_host_only_globals()
  test_addon_os_keeps_only_the_time_functions()
  test_addon_getfenv_and_loadstring_do_not_reach_the_real_globals()
  test_addon_rawget_and_pairs_on_g_see_globals_but_not_host_only_names()
  test_addon_write_through_g_is_a_global_removed_on_destroy()
  test_addon_errors_are_still_recorded_after_an_addon_sets_debug()
  test_a_failing_error_handler_still_records_after_an_addon_sets_debug()
  test_later_addons_still_load_after_an_addon_sets_io()
  test_a_golden_update_still_writes_after_an_addon_sets_io()
  test_debugprofilestop_still_works_after_an_addon_clears_os()
end
