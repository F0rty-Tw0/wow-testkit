-- Loading an addon's TOC files into a world: shared namespace, globals, require sentinel, skips and load errors.
local A = require("assert")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local H = require("tests.helpers.world")
local fs = require("fs")

local withWorld = H.withWorld

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local ADDONS_DIR = TEST_DIR .. "/fixtures/addons"
local SMOKE_DIR = TEST_DIR .. "/fixtures/smoke"
local LONG_CHUNK = "addon:LongPath/Deeply/Nested/Folder/Structure/For/Testing/Truncation/Of/Chunk/Names.lua"

math.randomseed(os.time())

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
  local root = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/") .. "/wow-testkit-addon-" .. os.time() .. "-" .. math.random(1, 1000000)
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

local function test_apply_saved_sets_saved_variable_globals()
  withWorld("retail", function(w)
    local _, info = load(w, "Mini")
    A.same(info.savedVariables, { "MiniDB" })
    Addon.applySaved(w, info, { MiniDB = { x = 1 } })
    A.same(_G.MiniDB, { x = 1 })
  end)
  A.eq(rawget(_G, "MiniDB"), nil)
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
  test_missing_xml_and_xml_script_are_errors()
  test_long_chunk_name_error_keeps_full_source()
  test_apply_saved_sets_saved_variable_globals()
  test_addon_code_cannot_reach_host_only_globals()
  test_addon_os_keeps_only_the_time_functions()
  test_addon_getfenv_and_loadstring_do_not_reach_the_real_globals()
  test_addon_rawget_and_pairs_on_g_see_globals_but_not_host_only_names()
  test_addon_write_through_g_is_a_global_removed_on_destroy()
end
