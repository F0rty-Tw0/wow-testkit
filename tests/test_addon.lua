-- Loading an addon's TOC files into a world: shared namespace, globals, require sentinel, skips and load errors.
local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local H = require("tests.helpers.world")
local Xml = require("ui.xml")
local fs = require("fs")

local withWorld = H.withWorld

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local ADDONS_DIR = TEST_DIR .. "/fixtures/addons"
local SMOKE_DIR = TEST_DIR .. "/fixtures/smoke"
local LONG_CHUNK = "addon:LongPath/Deeply/Nested/Folder/Structure/For/Testing/Truncation/Of/Chunk/Names.lua"

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

local function reportText(info)
  return table.concat(info.report, "\n")
end

local function test_files_run_in_order_sharing_one_namespace()
  withWorld("retail", function(w)
    local ns, info = load(w, "Mini")
    A.eq(info.status, "loaded")
    A.eq(ns.A.ok, true)
    A.eq(ns.B.sawA, true)
    A.same(w.errors, {})
  end)
end

local function test_addon_globals_reach_g_and_go_on_destroy()
  withWorld("retail", function(w)
    load(w, "Mini")
    A.eq(_G.MiniGlobal, 1)
  end)
  A.eq(rawget(_G, "MiniGlobal"), nil)
end

local function test_require_fallback_fails_like_a_nil_global_on_retail()
  withWorld("retail", function(w)
    load(w, "Order")
    A.contains(errorMessages(w), "global 'require'")
  end)
end

local function test_require_fallback_fails_with_invalid_import_on_forever()
  withWorld("forever", function(w)
    load(w, "Order")
    A.contains(errorMessages(w), "Invalid import")
  end)
end

local function test_undeclared_flavor_is_skipped_without_running_files()
  withWorld("vanilla", function(w)
    local ns, info = load(w, "WMStyle")
    A.eq(info.status, "skipped")
    A.eq(info.reason, "not declared")
    A.eq(info.declared, "not-declared")
    A.same(ns, {})
  end)
end

local function test_load_error_is_recorded_and_later_files_still_run()
  withWorld("retail", function(w)
    local ns = load(w, "Broken")
    A.eq(#w.errors, 1)
    A.contains(errorMessages(w), "addon:Broken/First.lua")
    A.eq(w.errors[1].source, "addon:Broken/First.lua")
    A.eq(ns.second, true)
  end)
end

-- Writes a one-file addon declaring interfaceLine to a temp dir and loads it on tbc.
local function loadOnTbc(interfaceLine)
  local root = Tmp.dir("addon")
  fs.mkdirp(root)
  fs.writeFile(root .. "/Temp.toc", interfaceLine .. "\n\nCore.lua\n")
  fs.writeFile(root .. "/Core.lua", "local _, ns = ...\nns.loaded = true\n")
  local ns, info
  withWorld("tbc", function(w)
    ns, info = Addon.load(w, { name = "Temp", root = root })
  end)
  return ns, info
end

local function test_outdated_interface_loads_with_a_report_line()
  local ns, info = loadOnTbc("## Interface-TBC: " .. (Flavors.get("tbc").tocVersion - 1))
  A.eq(info.status, "loaded")
  A.eq(info.declared, "outdated")
  A.contains(reportText(info), "outdated")
  A.eq(ns.loaded, true)
end

local function test_ahead_interface_loads_with_a_report_line()
  local ns, info = loadOnTbc("## Interface-TBC: " .. (Flavors.get("tbc").tocVersion + 1))
  A.eq(info.declared, "ahead")
  A.contains(reportText(info), "ahead")
  A.eq(ns.loaded, true)
end

local function test_missing_toc_file_is_an_error_and_later_files_load()
  withWorld("retail", function(w)
    local ns, info = load(w, "Missing")
    A.contains(errorMessages(w), "TOC lists missing file: addon:Missing/Gone.lua")
    A.contains(reportText(info), "Gone.lua")
    A.eq(ns.present, true)
  end)
end

-- Runs fn with Addon.gc recording its "stop" and "restart" calls (the real collectgarbage still runs); returns them.
local function gcCalls(fn)
  local gc, calls = Addon.gc, {}
  Addon.gc = function(opt)
    if opt ~= "count" then
      calls[#calls + 1] = opt
    end
    return gc(opt)
  end
  local ok, err = pcall(fn)
  Addon.gc = gc
  if not ok then
    error(err, 0)
  end
  return calls
end

local function test_the_gc_pauses_for_the_file_loop_only()
  local calls = gcCalls(function()
    withWorld("retail", function(w)
      load(w, "Mini")
    end)
  end)
  A.same(calls, { "stop", "restart" })
end

local function test_a_raising_file_still_restarts_the_gc()
  local root = Tmp.dir("addon")
  fs.mkdirp(root)
  fs.writeFile(root .. "/Raise.toc", "## Interface: 120100\n\nRaise.xml\n")
  local loadFile = Xml.loadFile
  Xml.loadFile = function()
    error("kit raised", 0)
  end
  local ok, err
  local calls = gcCalls(function()
    withWorld("retail", function(w)
      ok, err = pcall(Addon.load, w, { name = "Raise", root = root })
      A.eq(w.dev.loading, nil)
      A.same(w.dev.loads, {})
    end)
  end)
  Xml.loadFile = loadFile
  A.eq(ok, false)
  A.eq(err, "kit raised")
  A.same(calls, { "stop", "restart" })
end

local function test_a_nested_load_leaves_the_gc_stopped_until_the_outer_one_ends()
  local root = Tmp.dir("addon")
  fs.mkdirp(root)
  fs.writeFile(root .. "/Outer.toc", "## Interface: 120100\n\nOuter.xml\n")
  local loadFile = Xml.loadFile
  local calls = gcCalls(function()
    withWorld("retail", function(w)
      Xml.loadFile = function()
        Xml.loadFile = loadFile
        load(w, "Mini")
      end
      Addon.load(w, { name = "Outer", root = root })
    end)
  end)
  Xml.loadFile = loadFile
  A.same(calls, { "stop", "stop", "restart" })
end

-- Leaves 100000 unreachable tables for the next collection.
local function leaveGarbage()
  local junk = {}
  for i = 1, 100000 do
    junk[i] = { i }
  end
  return #junk
end

local function test_memory_never_goes_negative_when_the_addon_collects_garbage()
  local root = Tmp.dir("addon")
  fs.mkdirp(root)
  fs.writeFile(root .. "/Collect.toc", "## Interface: 120100\n\nCollect.lua\n")
  fs.writeFile(root .. "/Collect.lua", 'collectgarbage("collect")\n')
  leaveGarbage()
  withWorld("retail", function(w)
    Addon.load(w, { name = "Collect", root = root })
    A.same(w.errors, {})
    A.truthy(w.dev.loads[1].memoryKb >= 0, "memoryKb " .. w.dev.loads[1].memoryKb)
  end)
end

local function test_missing_xml_and_xml_script_are_errors()
  withWorld("retail", function(w)
    load(w, "Missing")
    A.contains(errorMessages(w), "TOC lists missing file: addon:Missing/Gone.xml")
    A.contains(errorMessages(w), "TOC lists missing file: addon:Missing/GoneToo.lua")
    A.eq(#w.errors, 3)
  end)
end

local function test_long_chunk_name_error_keeps_full_source()
  withWorld("retail", function(w)
    load(w, "LongPath")
    A.eq(#w.errors, 1)
    A.eq(w.errors[1].source, LONG_CHUNK)
  end)
end

local function test_apply_saved_sets_saved_variable_globals()
  withWorld("retail", function(w)
    local _, info = load(w, "Mini")
    A.same(info.savedVariables, { "MiniDB" })
    Addon.applySaved(w, info, { MiniDB = { x = 1 } })
    A.same(_G.MiniDB, { x = 1 })
  end)
  A.eq(rawget(_G, "MiniDB"), nil)
end

-- wiki TOC_format: SavedVariables are "Global variables"; no page splits a dotted name, so it is one key (as F2).
local function test_apply_saved_sets_a_dotted_name_as_one_global_assumed()
  local saved, nested
  withWorld("retail", function(w)
    Addon.applySaved(w, { savedVariables = { "Dotted.DB" }, savedVariablesPerCharacter = {} }, { ["Dotted.DB"] = 5 })
    saved, nested = rawget(_G, "Dotted.DB"), rawget(_G, "Dotted")
  end)
  A.same({ saved, nested, rawget(_G, "Dotted.DB") }, { 5, nil, nil })
end

local function test_collect_saved_reads_the_declared_globals()
  withWorld("retail", function(w)
    local info = { savedVariables = { "AccountDB", "UnsetDB" }, savedVariablesPerCharacter = { "CharDB" } }
    w:setGlobal("AccountDB", { a = 1 })
    w:setGlobal("CharDB", 5)
    w:setGlobal("OtherDB", 9)
    A.same(Addon.collectSaved(w, info), { AccountDB = { a = 1 }, CharDB = 5 })
    A.same(Addon.collectSaved(w, { status = "skipped" }), {})
  end)
end

local function test_no_toc_for_flavor_is_skipped()
  withWorld("vanilla", function(w)
    local _, info = Addon.load(w, { name = "MainlineToc", root = SMOKE_DIR .. "/MainlineToc" })
    A.eq(info.status, "skipped")
    A.eq(info.reason, "no TOC for this flavor")
    A.same(info.report, {})
  end)
end

local function test_unknown_addon_name_is_an_error()
  withWorld("vanilla", function(w)
    local ok, err = pcall(Addon.load, w, { name = "Nope", root = SMOKE_DIR .. "/MainlineToc" })
    A.eq(ok, false)
    A.contains(tostring(err), "cannot read TOC")
  end)
end

return function()
  test_files_run_in_order_sharing_one_namespace()
  test_addon_globals_reach_g_and_go_on_destroy()
  test_require_fallback_fails_like_a_nil_global_on_retail()
  test_require_fallback_fails_with_invalid_import_on_forever()
  test_undeclared_flavor_is_skipped_without_running_files()
  test_no_toc_for_flavor_is_skipped()
  test_unknown_addon_name_is_an_error()
  test_load_error_is_recorded_and_later_files_still_run()
  test_outdated_interface_loads_with_a_report_line()
  test_ahead_interface_loads_with_a_report_line()
  test_missing_toc_file_is_an_error_and_later_files_load()
  test_the_gc_pauses_for_the_file_loop_only()
  test_a_raising_file_still_restarts_the_gc()
  test_a_nested_load_leaves_the_gc_stopped_until_the_outer_one_ends()
  test_memory_never_goes_negative_when_the_addon_collects_garbage()
  test_missing_xml_and_xml_script_are_errors()
  test_long_chunk_name_error_keeps_full_source()
  test_apply_saved_sets_saved_variable_globals()
  test_apply_saved_sets_a_dotted_name_as_one_global_assumed()
  test_collect_saved_reads_the_declared_globals()
end
