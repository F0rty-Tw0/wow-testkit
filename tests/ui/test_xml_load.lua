-- XML file loader: Include and Script walking in document order, missing and malformed files, unknown elements.
local A = require("assert")
local Addon = require("addon")
local H = require("tests.helpers.xml")
local Tmp = require("tests.helpers.tmp")
local World = require("tests.helpers.world")
local Xml = require("ui.xml")
local XmlBuild = require("ui.xml_build")
local fs = require("fs")

local function reportText(ctx)
  return table.concat(ctx.report, "\n")
end

local function count(text, needle)
  local n = 0
  for _ in text:gmatch(needle) do
    n = n + 1
  end
  return n
end

local function test_script_files_run_in_document_order_relative_to_the_xml_assumed()
  H.withXml({
    ["UI/Main.xml"] = '<Ui><Script file="A.lua"/><Include file="Sub\\Inner.xml"/><Script file="B.lua"/></Ui>',
    ["UI/Sub/Inner.xml"] = '<Ui><Script file="I.lua"/></Ui>',
    ["UI/A.lua"] = 'local _, ns = ...; ns.log = (ns.log or "") .. "A"',
    ["UI/B.lua"] = 'local _, ns = ...; ns.log = ns.log .. "B"',
    ["UI/Sub/I.lua"] = 'local _, ns = ...; ns.log = ns.log .. "I"',
  }, function(w, ctx)
    A.eq(H.load(w, ctx, "UI/Main.xml"), true)
    A.eq(ctx.ns.log, "AIB")
  end)
end

local function test_a_backslash_path_to_the_xml_loads()
  H.withXml({
    ["UI/Main.xml"] = '<Ui><Script file="A.lua"/></Ui>',
    ["UI/A.lua"] = "local _, ns = ...; ns.ran = true",
  }, function(w, ctx)
    A.eq(H.load(w, ctx, "UI\\Main.xml"), true)
    A.eq(ctx.ns.ran, true)
  end)
end

-- assumed: no doc names it, but Auctionator, Plumber, Prat and RareScanner ship `<Include file="X.lua"/>` and work in the client.
local function test_an_include_of_a_lua_file_runs_it_like_a_script_assumed()
  H.withXml({
    ["Ui.xml"] = '<Ui><Include file="Sub\\Inc.LUA"/><Script>local _, ns = ...; ns.log = ns.log .. "S"</Script></Ui>',
    ["Sub/Inc.LUA"] = 'local _, ns = ...; ns.log = "I"',
  }, function(w, ctx)
    A.eq(H.load(w, ctx, "Ui.xml"), true)
    A.eq(ctx.ns.log, "IS")
    A.same(w.errors, {})
  end)
end

-- source: wiki XML/Script, "Executed when reached by the XML parser, going from top to bottom."
local function test_inline_script_runs_and_errors_name_the_xml_line()
  H.withXml({
    ["Ui.xml"] = '<Ui>\n<Script>local _, ns = ...; ns.ran = true</Script>\n<Script>\nerror("boom")</Script>\n</Ui>',
  }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(ctx.ns.ran, true)
    A.contains(w.errors[1].message, "addon:XmlT/Ui.xml:4:") -- the body starts on line 3; error() is on its second line
  end)
end

local function test_inline_script_that_does_not_compile_is_reported_not_raised()
  H.withXml({ ["Ui.xml"] = "<Ui><Script>local = </Script><Script>local _, ns = ...; ns.after = true</Script></Ui>" }, function(w, ctx)
    A.eq(H.load(w, ctx, "Ui.xml"), true)
    A.contains(w.errors[1].message, "addon:XmlT/Ui.xml:1:")
    A.eq(ctx.ns.after, true)
  end)
end

local function test_missing_files_are_reported_and_loading_continues()
  H.withXml({
    ["Ui.xml"] = '<Ui><Script file="Nope.lua"/><Include file="Gone.xml"/><Script>local _, ns = ...; ns.after = true</Script></Ui>',
  }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(w.errors[1].message, "TOC lists missing file: addon:XmlT/Nope.lua")
    A.contains(reportText(ctx), "Gone.xml: cannot read XML file")
    A.eq(ctx.ns.after, true)
  end)
end

-- source: assumed (row X23) inline directives are a TOC feature; XML file= is read as written.
local function test_script_file_reads_a_bracketed_suffix_as_part_of_the_path_assumed()
  H.withXml({
    ["Ui.xml"] = '<Ui><Script file="A.lua [AllowLoadGameType cata]"/></Ui>',
    ["A.lua"] = "local _, ns = ...; ns.ran = true",
  }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(w.errors[1].message, "addon:XmlT/A.lua [AllowLoadGameType cata]")
    A.eq(ctx.ns.ran, nil)
  end)
end

local function test_malformed_xml_is_one_error_and_returns_false()
  H.withXml({ ["Ui.xml"] = "<Ui><Frame></Ui>" }, function(w, ctx)
    A.eq(H.load(w, ctx, "Ui.xml"), false)
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "addon:XmlT/Ui.xml: line 1")
  end)
end

local function test_unknown_element_is_reported_once_per_file_assumed() -- (X16)
  H.withXml({ ["Ui.xml"] = '<Ui><Font name="F"/><Font name="G"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(count(reportText(ctx), "unsupported XML <Font> ignored"), 1)
  end)
end

local function test_a_file_that_includes_itself_stops_at_the_cycle()
  H.withXml({ ["Ui.xml"] = '<Ui><Include file="Ui.xml"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(count(reportText(ctx), "Ui%.xml: include cycle ignored"), 1)
  end)
end

local function test_include_cycle_through_a_parent_folder_path_stops()
  H.withXml({
    ["UI/Ui.xml"] = '<Ui><Include file="Sub/Back.xml"/></Ui>',
    ["UI/Sub/Back.xml"] = '<Ui><Include file="../Ui.xml"/></Ui>',
  }, function(w, ctx)
    H.load(w, ctx, "UI/Ui.xml")
    A.eq(count(reportText(ctx), "UI/Ui%.xml: include cycle ignored"), 1)
  end)
end

-- On Windows a.xml and A.xml are one file, so the cycle guard keys on the lowercased path.
local function test_include_cycle_through_a_different_case_stops_at_the_first_repeat()
  H.withXml({
    ["a.xml"] = '<Ui><Script>local _, ns = ...; ns.count = (ns.count or 0) + 1</Script><Include file="A.xml"/></Ui>',
  }, function(w, ctx)
    H.load(w, ctx, "a.xml")
    A.eq(ctx.ns.count, 1)
    A.eq(count(reportText(ctx), "A%.xml: include cycle ignored"), 1)
  end)
end

-- A world with no widgets installed (the kit's own addon-loading tests) has no layout state to invalidate.
local function test_a_file_without_frames_loads_into_a_world_without_widgets()
  local root = Tmp.dir("xml") .. "/XmlT"
  fs.mkdirp(root)
  fs.writeFile(root .. "/Ui.xml", "<Ui><Script>local _, ns = ...; ns.ran = true</Script></Ui>")
  World.withWorld("retail", function(w)
    local ctx = Addon.context(w, "XmlT", root)
    A.eq(Xml.loadFile(w, "Ui.xml", ctx), true)
    A.eq(ctx.ns.ran, true)
  end)
end

-- Runs fn under XmlBuild.guard as Ui.xml line 7; returns the reported messages.
local function guarded(fn)
  local messages = {}
  H.withXml({}, function(w, ctx)
    local session = XmlBuild.session(ctx)
    session.file = { path = "Ui.xml" }
    XmlBuild.guard(w, session, 7, fn)
    for i, entry in ipairs(w.errors) do
      messages[i] = tostring(entry.message)
    end
  end)
  return messages
end

local function test_guard_keeps_an_addon_position()
  A.same(
    guarded(function()
      error("addon:XmlT/Core.lua:3: boom", 0)
    end),
    { "addon:XmlT/Core.lua:3: boom" }
  )
end

local function test_guard_puts_the_xml_position_in_place_of_a_kit_position()
  A.same(
    guarded(function()
      XmlBuild.substituteParent("$parentX", {})
    end),
    { "addon:XmlT/Ui.xml:7: attempt to call method 'GetName' (a nil value)" }
  )
end

local function test_guard_prefixes_a_message_without_a_position()
  A.same(
    guarded(function()
      error("plain", 0)
    end),
    { "addon:XmlT/Ui.xml:7: plain" }
  )
end

return function()
  test_script_files_run_in_document_order_relative_to_the_xml_assumed()
  test_a_backslash_path_to_the_xml_loads()
  test_an_include_of_a_lua_file_runs_it_like_a_script_assumed()
  test_inline_script_runs_and_errors_name_the_xml_line()
  test_inline_script_that_does_not_compile_is_reported_not_raised()
  test_missing_files_are_reported_and_loading_continues()
  test_script_file_reads_a_bracketed_suffix_as_part_of_the_path_assumed()
  test_malformed_xml_is_one_error_and_returns_false()
  test_unknown_element_is_reported_once_per_file_assumed()
  test_a_file_that_includes_itself_stops_at_the_cycle()
  test_include_cycle_through_a_parent_folder_path_stops()
  test_include_cycle_through_a_different_case_stops_at_the_first_repeat()
  test_a_file_without_frames_loads_into_a_world_without_widgets()
  test_guard_keeps_an_addon_position()
  test_guard_puts_the_xml_position_in_place_of_a_kit_position()
  test_guard_prefixes_a_message_without_a_position()
end
