-- Blizzard UI layer (blizzard_ui.lua, scenario_blizzard.lua): Blizzard's own UI addons load from a client extract
-- before the addon under test, dependencies first, secure, with their errors kept apart. Every extract here is a
-- kit-authored mini one (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local Bindings = require("bindings")
local Json = require("json")
local Scenario = require("scenario")
local SessionH = require("tests.helpers.session")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local function test_dependencies_load_first_and_addon_loaded_fires_per_addon()
  B.run(B.mini(), { targets = { "Blizzard_MiniBar" } }, function(s)
    A.same(_G.MiniLog, { "base", "adl:Blizzard_MiniBase", "bar", "more", "adl:Blizzard_MiniBar", "adl:Probe" })
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniBase", "Blizzard_MiniBar" })
    A.eq(_G.MiniBar:GetName(), "MiniBar") -- the XML frame exists before the addon under test loads
  end)
end

local function test_mixed_case_paths_resolve_in_a_lowercase_extract()
  local asked, readFile, exists = {}, fs.readFile, fs.exists
  local function spy(real)
    return function(path)
      asked[#asked + 1] = path
      return real(path)
    end
  end
  fs.readFile, fs.exists = spy(readFile), spy(exists)
  local ok, err = pcall(B.run, B.mini(), { targets = { "Blizzard_MiniBar" } }, function() end)
  fs.readFile, fs.exists = readFile, exists
  assert(ok, err)
  local inside = 0
  for _, path in ipairs(asked) do
    local rest = path:match("/code/(.*)$")
    if rest then
      inside = inside + 1
      A.eq(rest, rest:lower(), path) -- TOC says MiniBar.xml, XML says MiniBar.lua; the reads are lowercase
    end
  end
  A.truthy(inside >= 5, "toc + xml + lua files were read")
end

local function test_blizzard_definitions_replace_kit_fakes_and_the_rest_stay()
  B.run(B.mini(), { targets = { "Blizzard_MiniBase" } }, function()
    A.eq(_G.FACTION_HORDE, "Mini Horde") -- kit value was "Horde"
    A.truthy(_G.UIParent ~= nil and _G.GameTooltip ~= nil, "untouched kit fakes remain")
  end)
end

local function test_errors_in_blizzard_files_stay_out_of_w_errors_and_loading_continues()
  local addons = B.mini({ blizzard_minibar = { files = { ["minimore.lua"] = 'error("mini boom")' } } })
  local report = B.run(addons, { targets = { "Blizzard_MiniBar" } }, function(s)
    A.eq(#s.w.errors, 0)
    A.contains(s.w.blizzard.errors[1].message, "mini boom")
    A.eq(s.w.blizzard.errors[1].addon, "Blizzard_MiniBar")
    -- the next addon step still ran
    A.same(_G.MiniLog, { "base", "adl:Blizzard_MiniBase", "bar", "adl:Blizzard_MiniBar", "adl:Probe" })
  end)
  A.eq(report.status, "pass") -- the addon under test is judged on its own errors
end

local function test_later_blizzard_handler_errors_do_not_fail_the_addon()
  local late = 'local f = CreateFrame("Frame"); f:RegisterEvent("PLAYER_ENTERING_WORLD")\n'
    .. 'f:SetScript("OnEvent", function() error("late boom") end)\n'
  local addons = B.mini({ blizzard_minibar = { files = { ["minimore.lua"] = late } } })
  local report = B.run(addons, { targets = { "Blizzard_MiniBar" } }, function(s)
    A.eq(#s.w.errors, 0)
    A.contains(s.w.blizzard.errors[1].message, "late boom")
    A.eq(s.w.blizzard.errors[1].addon, "Blizzard_MiniBar")
  end)
  A.eq(report.status, "pass")
end

local function test_errors_without_a_blizzard_position_are_found_on_the_stack()
  local long = "averyveryverylongfilenamethatpushesthechunknamepastluaidsize.lua"
  -- "addon:Blizzard_MiniBar/" plus this name is 54 characters: Lua keeps the last 52, cutting inside "addon:".
  local cut = "cutsinsidetheaddonprefixabc.lua"
  local toc = "## Interface: 120100\n## Dependencies: Blizzard_MiniBase\n" .. long .. "\n" .. cut .. "\nMiniMore.lua\n"
  local files = { [long] = 'error("long boom")', [cut] = 'error("cut boom")', ["minimore.lua"] = 'error("bare boom", 0)' }
  local addons = B.mini({ blizzard_minibar = { toc = toc, files = files } })
  B.run(addons, { targets = { "Blizzard_MiniBar" } }, function(s)
    A.eq(#s.w.errors, 0)
    A.eq(#s.w.blizzard.errors, 3)
    A.contains(s.w.blizzard.errors[1].message, "long boom")
    A.contains(s.w.blizzard.errors[2].message, "...don:Blizzard_MiniBar/" .. cut .. ":1: cut boom")
    A.eq(s.w.blizzard.errors[3].message, "bare boom")
    for _, entry in ipairs(s.w.blizzard.errors) do
      A.eq(entry.addon, "Blizzard_MiniBar")
    end
  end)
end

local function test_a_blizzard_seterrorhandler_keeps_the_layer_handler()
  local takeover = 'seterrorhandler(function() MiniHandled = true end)\nerror("same file boom")\n'
  local addons = B.mini()
  local base = addons.blizzard_minibase.files
  base["minibase.lua"] = base["minibase.lua"] .. takeover
  addons.blizzard_minibar.files["minimore.lua"] = 'error("next addon boom")'
  B.run(addons, { targets = { "Blizzard_MiniBar" } }, function(s)
    A.eq(_G.MiniHandled, true) -- Blizzard's handler took the rest of its own addon's load
    A.eq(#s.w.blizzard.errors, 1)
    A.contains(s.w.blizzard.errors[1].message, "next addon boom")
  end)
end

local function test_a_utf8_bom_at_the_start_of_a_blizzard_file_is_skipped()
  local addons = B.mini({ blizzard_minibar = { files = { ["minimore.lua"] = "\239\187\191MiniBom = true\n" } } })
  B.run(addons, { targets = { "Blizzard_MiniBar" } }, function(s)
    A.eq(_G.MiniBom, true)
    A.eq(#s.w.blizzard.errors, 0)
  end)
end

local function test_probe_errors_still_fail_the_report()
  local ok, err = pcall(B.run, B.mini(), { targets = { "Blizzard_MiniBase" }, lua = 'error("probe boom")' }, function() end)
  A.eq(ok, false)
  A.contains(err, "probe boom")
end

local function test_no_extract_is_a_noop_with_a_note() -- D1 fallback
  local s = Scenario.new({ addon = "Probe", root = B.probe(), flavor = "retail", blizzardUi = true, findClient = function() end })
  s:login()
  A.same(s.w.blizzard.loaded, {})
  A.contains(table.concat(s.notes, "\n"), "no client extract; kit fakes only")
  s.w:destroy()
end

local function test_find_client_supplies_the_extract_when_none_is_given()
  local ex = B.extract(Tmp.dir("bzfind"), B.mini({ blizzard_actionbar = { toc = "## Dependencies: Blizzard_MiniBase\n" } }))
  local asked = {}
  local s = Scenario.new({
    addon = "Probe",
    root = B.probe(),
    flavor = "retail",
    blizzardUi = true,
    findClient = function(flavor)
      asked[#asked + 1] = flavor
      return ex
    end,
  })
  local ok, err = pcall(s.login, s)
  local loaded, client = s.w.blizzard and s.w.blizzard.loaded, s.w.client
  s.w:destroy()
  assert(ok, err)
  A.same(asked, { "retail" })
  A.eq(client, ex) -- the world reads the same extract (art, strings)
  A.same(loaded, { "Blizzard_MiniBase", "Blizzard_ActionBar" })
end

local function test_missing_target_is_skipped_not_raised()
  B.run(B.mini(), { targets = { "Blizzard_Nope", "Blizzard_MiniBase" } }, function(s)
    A.same(s.w.blizzard.skipped, { { name = "Blizzard_Nope", reason = "not in extract" } })
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniBase" }) -- the other targets keep loading
  end)
end

-- source: assumed (row BU2) a classic-only dependency is not part of a retail load.
local function test_dependencies_of_other_game_types_are_dropped_assumed()
  B.run(B.mini(), { targets = { "Blizzard_MiniBar" } }, function(s)
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniBase", "Blizzard_MiniBar" })
    A.same(s.w.blizzard.skipped, {}) -- Blizzard_Gone is classic-only: neither loaded nor skipped
  end)
end

local function test_flavor_suffixed_toc_is_found_in_lowercase()
  local addons = B.mini({
    blizzard_minisuffix = { toc = "Suffix.lua\n", tocFile = "blizzard_minisuffix_mainline.toc", files = { ["suffix.lua"] = "MiniSuffix = true" } },
  })
  B.run(addons, { targets = { "Blizzard_MiniSuffix" } }, function(s)
    A.same(s.w.blizzard.loaded, { "Blizzard_MiniSuffix" })
    A.eq(_G.MiniSuffix, true)
  end)
end

-- source: confirmed (row BU3) on retail [Family] is the Mainline folder and [Game] the Standard one.
local function test_family_and_game_path_tokens_resolve()
  local toc = "## Interface: 120100\n[Family]\\Fam.lua\n[Game]\\Gam.lua\n"
  local files = { ["mainline/fam.lua"] = "MiniFam = true", ["standard/gam.lua"] = "MiniGam = true" }
  B.run(B.mini({ blizzard_minitokens = { toc = toc, files = files } }), { targets = { "Blizzard_MiniTokens" } }, function(s)
    A.same({ _G.MiniFam, _G.MiniGam }, { true, true })
    A.same(s.w.blizzard.notes, {})
  end)
end

local function test_loaded_blizzard_addons_count_as_loaded()
  B.run(B.mini(), { targets = { "Blizzard_MiniBar" } }, function()
    A.same({ _G.C_AddOns.IsAddOnLoaded("Blizzard_MiniBar") }, { true, true })
    A.same({ _G.C_AddOns.IsAddOnLoaded("Blizzard_Gone") }, { false, false })
  end)
end

local function test_bindings_xml_registers_commands_and_runs_them()
  B.run(B.mini(), { targets = { "Blizzard_MiniBar" } }, function(s)
    A.truthy(s.w.bindings.commands.MINI_TOGGLE ~= nil, "registered")
    Bindings.run(s.w, "MINI_TOGGLE", "down")
    A.eq(_G.MiniLog[#_G.MiniLog], "toggle")
  end)
end

-- source: assumed (row BU1) retail's default bindings file is Blizzard_FrameXML's bindings_standard.xml.
local function test_default_bindings_xml_loads_with_the_layer_assumed()
  B.run(B.mini(), { targets = { "Blizzard_MiniBase" } }, function(s)
    A.contains(s.w.blizzard.defaultBindings, "addons/blizzard_framexml/bindings_standard.xml")
    Bindings.run(s.w, "MINI_DEFAULT", "down")
    A.eq(_G.MiniLog[#_G.MiniLog], "default")
  end)
  local addons = B.mini()
  addons.blizzard_framexml = nil
  B.run(addons, { targets = { "Blizzard_MiniBase" } }, function(s)
    A.eq(s.w.blizzard.defaultBindings, nil)
    A.contains(table.concat(s.w.blizzard.notes, "\n"), "no default Bindings.xml")
    A.eq(#s.w.blizzard.errors, 0)
  end)
  local s = Scenario.new({ addon = "Probe", root = B.probe(), flavor = "retail" }) -- no layer
  s:login()
  A.eq(s.w.bindings and s.w.bindings.commands.MINI_DEFAULT, nil)
  s.w:destroy()
end

local function test_blizzard_code_runs_secure() -- R6: the folder name never taints Blizzard code
  B.run(B.mini(), { targets = { "Blizzard_MiniBase" } }, function()
    A.eq(_G.MiniSecure, true)
  end)
end

local function test_tainted_caller_keeps_taint_in_blizzard_code() -- TS15: Blizzard code never launders taint
  B.run(B.mini(), { targets = { "Blizzard_MiniBase" }, lua = "securecall(MiniCheck)" }, function()
    A.eq(_G.MiniSeen, false)
  end)
end

local function test_session_snapshot_reports_the_layer()
  local ex = B.extract(Tmp.dir("bzs"), B.mini())
  SessionH.withSession({ blizzardUi = { targets = { "Blizzard_MiniBar" } }, extract = ex.dir }, function(sess)
    local snap = sess:call("snapshot")
    A.eq(snap.session.blizzard.enabled, true)
    A.same(snap.session.blizzard.loaded, { "Blizzard_MiniBase", "Blizzard_MiniBar" })
    A.truthy(SessionH.item(snap, "MiniBar") ~= nil, "Blizzard frame is in the snapshot")
  end)
  SessionH.withSession({}, function(sess)
    A.eq(sess:call("snapshot").session.blizzard.enabled, false)
  end)
end

local function test_xml_script_paths_fall_back_to_the_addon_root_assumed()
  local addons = B.mini({
    blizzard_minisub = {
      toc = "## Interface: 120100\nSub\\Ui.xml\n",
      files = {
        ["sub/ui.xml"] = '<Ui><Script file="Sub\\Item.lua"/></Ui>',
        ["sub/item.lua"] = "MiniSub = (MiniSub or 0) + 1",
      },
    },
  })
  B.run(addons, { targets = { "Blizzard_MiniSub" } }, function(s)
    A.same({ _G.MiniSub, #s.w.blizzard.errors }, { 1, 0 })
  end)
end

local function test_invalid_utf8_in_a_blizzard_error_still_encodes_a_snapshot()
  local addons = B.mini({ blizzard_minibar = { files = { ["minimore.lua"] = 'error("bad \\187 byte")' } } })
  local ex = B.extract(Tmp.dir("bzu"), addons)
  SessionH.withSession({ blizzardUi = { targets = { "Blizzard_MiniBar" } }, extract = ex.dir }, function(sess)
    local text = sess:handle("snapshot", {})
    A.eq(text:find("\187", 1, true), nil) -- the raw byte is gone: JSON text is UTF-8
    local first = Json.decode(text).session.blizzard.firstErrors[1]
    A.contains(first.message, "bad \239\191\189 byte")
  end)
end

return function()
  test_invalid_utf8_in_a_blizzard_error_still_encodes_a_snapshot()
  test_xml_script_paths_fall_back_to_the_addon_root_assumed()
  test_dependencies_load_first_and_addon_loaded_fires_per_addon()
  test_mixed_case_paths_resolve_in_a_lowercase_extract()
  test_blizzard_definitions_replace_kit_fakes_and_the_rest_stay()
  test_errors_in_blizzard_files_stay_out_of_w_errors_and_loading_continues()
  test_later_blizzard_handler_errors_do_not_fail_the_addon()
  test_errors_without_a_blizzard_position_are_found_on_the_stack()
  test_a_blizzard_seterrorhandler_keeps_the_layer_handler()
  test_a_utf8_bom_at_the_start_of_a_blizzard_file_is_skipped()
  test_probe_errors_still_fail_the_report()
  test_no_extract_is_a_noop_with_a_note()
  test_find_client_supplies_the_extract_when_none_is_given()
  test_missing_target_is_skipped_not_raised()
  test_dependencies_of_other_game_types_are_dropped_assumed()
  test_flavor_suffixed_toc_is_found_in_lowercase()
  test_family_and_game_path_tokens_resolve()
  test_loaded_blizzard_addons_count_as_loaded()
  test_bindings_xml_registers_commands_and_runs_them()
  test_default_bindings_xml_loads_with_the_layer_assumed()
  test_blizzard_code_runs_secure()
  test_tainted_caller_keeps_taint_in_blizzard_code()
  test_session_snapshot_reports_the_layer()
end
