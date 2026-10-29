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

-- Lua 5.1's loadstring runs a chunk that starts with ESC as unverified bytecode.
local function test_a_precompiled_toc_file_is_reported_and_not_run()
  withWorld("retail", function(w)
    local ns = Addon.load(w, { name = "BinToc", root = tempAddon("BinToc", "\27Lua\0\0\0\0") })
    A.contains(errorMessages(w), "addon:BinToc/Core.lua: the chunk is precompiled bytecode, which is never run")
    A.eq(#w.errors, 1)
    A.same(ns, {})
  end)
end

local function test_addon_loadstring_refuses_precompiled_chunks()
  withWorld("retail", function(w)
    local source = 'local _, ns = ...; ns.fn, ns.err = loadstring("\\27Lua"); ns.ok = loadstring("return 1")'
    local ns = Addon.load(w, { name = "BinLoad", root = tempAddon("BinLoad", source) })
    A.same(w.errors, {})
    A.eq(ns.fn, nil)
    A.eq(ns.err, "the chunk is precompiled bytecode, which is never run")
    A.eq(ns.ok(), 1)
  end)
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

-- An addon's write to a host-only name stays in its view: it reads back what it wrote, while the kit's _G keeps the host
-- value, so kit code reading the global io is never left without it until w:destroy.
local function test_an_addon_write_to_io_leaves_the_host_io()
  local hostIo = io
  local source = "local _, ns = ...\nio = nil\nns.cleared = type(io)\nio = 5\nns.set = io\n"
  withWorld("retail", function(w)
    local ns = Addon.load(w, { name = "IoClear", root = tempAddon("IoClear", source) })
    A.same({ errorMessages(w), ns.cleared, ns.set, rawget(_G, "io") == hostIo }, { "", "nil", 5, true })
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

local FENV_PROBE = [[
local _, ns = ...
ns.level1 = getfenv(1) == _G
ns.noArg = getfenv() == _G
ns.ofOwnFunction = getfenv(function() end) == _G
ns.ofOtherAddon = getfenv(FenvOtherFn) == _G
ns.ofOtherAddonG = getfenv(FenvOtherGFn) == _G
]]
local FENV_OTHER = "function FenvOtherFn() end\nFenvOtherGFn = setfenv(function() end, _G)\n"

-- Lua 5.1 manual getfenv: the environment of the function at that level; the client loads every addon file with
-- the one _G.
local function test_addon_getfenv_returns_the_addons_g()
  withWorld("retail", function(w)
    Addon.load(w, { name = "FenvOther", root = tempAddon("FenvOther", FENV_OTHER) })
    local ns = Addon.load(w, { name = "FenvProbe", root = tempAddon("FenvProbe", FENV_PROBE) })
    local seen = { ns.level1, ns.noArg, ns.ofOwnFunction, ns.ofOtherAddon, ns.ofOtherAddonG }
    A.same({ errorMessages(w), seen }, { "", { true, true, true, true, true } })
  end)
end

local THREAD_ENV = [[
local _, ns = ...
local mine = setmetatable({ marker = "mine" }, { __index = _G })
setfenv(0, mine)
ns.thread = getfenv(0) == mine
ns.chunk = loadstring("return marker")()
]]

-- Lua 5.1 manual setfenv: "As a special case, when f is 0 setfenv changes the environment of the running thread";
-- loadstring gives new chunks that environment. Kit code keeps the real _G meanwhile.
local function test_addon_setfenv_0_changes_the_addon_thread_env_but_not_the_kits()
  local hostG, kitThread, kitChunk = _G, nil, nil
  withWorld("retail", function(w)
    local ns = Addon.load(w, { name = "ThreadEnv", root = tempAddon("ThreadEnv", THREAD_ENV) })
    kitThread = getfenv(0) == hostG
    kitChunk = getfenv(assert(loadstring("return 1"))) == hostG
    A.same({ errorMessages(w), ns.thread, ns.chunk }, { "", true, "mine" })
  end)
  A.same({ kitThread, kitChunk }, { true, true })
end

local SETFENV_LEVEL = [[
local _, ns = ...
local mine = setmetatable({}, { __index = _G })
ns.returned = setfenv(1, mine) ~= nil
LevelProbe = 1
ns.inMine = rawget(mine, "LevelProbe")
setfenv(1, 5)
]]

local function test_addon_setfenv_level_targets_the_addon_function_and_misuse_names_its_line()
  withWorld("retail", function(w)
    local ns = Addon.load(w, { name = "FenvLevel", root = tempAddon("FenvLevel", SETFENV_LEVEL) })
    A.same({ ns.returned, ns.inMine, rawget(_G, "LevelProbe") }, { true, 1, nil })
    A.eq(errorMessages(w), "addon:FenvLevel/Core.lua:6: bad argument #2 to 'setfenv' (table expected, got number)")
  end)
end

local OS_KEYS = [[
local _, ns = ...
ns.keys = {}
for key in pairs(os) do
  ns.keys[#ns.keys + 1] = key
end
table.sort(ns.keys)
ns.exit = os.exit
]]

local function test_addon_os_holds_exactly_the_time_functions()
  withWorld("retail", function(w)
    local ns = Addon.load(w, { name = "OsKeys", root = tempAddon("OsKeys", OS_KEYS) })
    A.same({ errorMessages(w), ns.keys, ns.exit }, { "", { "clock", "date", "difftime", "time" }, nil })
  end)
end

local OWN_DEBUG_READER = [[
local _, ns = ...
ns.seen = { debug, _G.debug, rawget(_G, "debug") }
for key, value in pairs(_G) do
  if key == "debug" then
    ns.seen[4] = value
  end
end
]]

-- Only the host's values are hidden: a global an addon assigns under a host-only name is an ordinary global.
local function test_a_host_only_name_an_addon_assigns_is_seen_by_other_addons()
  local seen
  withWorld("retail", function(w)
    Addon.load(w, { name = "OwnDebug", root = tempAddon("OwnDebug", "debug = 7\n") })
    local ns = Addon.load(w, { name = "OwnDebugReader", root = tempAddon("OwnDebugReader", OWN_DEBUG_READER) })
    seen = { errorMessages(w), ns.seen }
  end)
  A.same(seen, { "", { 7, 7, 7, 7 } })
end

return function()
  test_a_precompiled_toc_file_is_reported_and_not_run()
  test_addon_loadstring_refuses_precompiled_chunks()
  test_addon_os_holds_exactly_the_time_functions()
  test_a_host_only_name_an_addon_assigns_is_seen_by_other_addons()
  test_addon_getfenv_returns_the_addons_g()
  test_addon_setfenv_0_changes_the_addon_thread_env_but_not_the_kits()
  test_addon_setfenv_level_targets_the_addon_function_and_misuse_names_its_line()
  test_addon_code_cannot_reach_host_only_globals()
  test_addon_os_keeps_only_the_time_functions()
  test_addon_getfenv_and_loadstring_do_not_reach_the_real_globals()
  test_addon_rawget_and_pairs_on_g_see_globals_but_not_host_only_names()
  test_addon_write_through_g_is_a_global_removed_on_destroy()
  test_addon_errors_are_still_recorded_after_an_addon_sets_debug()
  test_a_failing_error_handler_still_records_after_an_addon_sets_debug()
  test_later_addons_still_load_after_an_addon_sets_io()
  test_an_addon_write_to_io_leaves_the_host_io()
  test_a_golden_update_still_writes_after_an_addon_sets_io()
  test_debugprofilestop_still_works_after_an_addon_clears_os()
end
