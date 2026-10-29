-- Loading an addon whose TOC lists an XML file: the XML builds at its TOC position, between the Lua files around it.
local A = require("assert")
local Addon = require("addon")
local Flavors = require("tools.flavors")
local H = require("tests.helpers.framexml")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local ADDONS_DIR = TEST_DIR .. "/fixtures/addons"
local SCREEN = { width = 1000, height = 800 }

local function load(w, name)
  return Addon.load(w, { name = name, root = ADDONS_DIR .. "/" .. name })
end

local function withXmlWorld(fn)
  H.withFrameXML("retail", function(w)
    local log = {}
    w:setGlobal("XmlUiLog", function(entry)
      log[#log + 1] = entry
    end)
    fn(w, log)
  end, { screen = SCREEN })
end

local function test_xml_builds_at_its_toc_position()
  withXmlWorld(function(w, log)
    local ns = load(w, "XmlUi")
    A.eq(ns.seeFrame, false) -- Early.lua runs before Ui.xml
    A.same(ns.order, { "early", "inline", "late" }) -- the inline Script runs in document order
    A.same(log, { "onload" }) -- OnLoad ran while Ui.xml loaded, before Late.lua
    -- Centered 200x100 on 1000x800: left = 500 - 100 = 400, bottom = 400 - 50 = 350.
    A.same(ns.rect, { 400, 350, 200, 100 })
  end)
end

-- Loads an addon whose TOC lists Ui.xml (the given text) then Late.lua; passes the world, ns and the load info to fn.
local function withBrokenXml(xml, fn)
  local root = Tmp.dir("addon") .. "/XmlBad"
  fs.mkdirp(root)
  fs.writeFile(root .. "/XmlBad.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nUi.xml\nLate.lua\n")
  fs.writeFile(root .. "/Ui.xml", xml)
  fs.writeFile(root .. "/Late.lua", "local _, ns = ...; ns.late = true")
  H.withFrameXML("retail", function(w)
    local ns, info = Addon.load(w, { name = "XmlBad", root = root })
    fn(w, ns, info)
  end, { screen = SCREEN })
end

local function reportedAt(w, line)
  local found = {}
  for _, entry in ipairs(w.errors) do
    if tostring(entry.message):find("addon:XmlBad/Ui.xml:" .. line .. ":", 1, true) then
      found[#found + 1] = entry
    end
  end
  return #found
end

local function test_a_frame_anchored_to_itself_is_reported_and_the_load_goes_on()
  local xml = '<Ui>\n<Frame name="SelfA"><Anchors><Anchor point="TOP" relativeTo="SelfA"/></Anchors></Frame>\n<Frame name="After"/></Ui>'
  withBrokenXml(xml, function(w, ns)
    A.eq(reportedAt(w, 2), 1)
    A.eq(_G.After ~= nil, true)
    A.eq(ns.late, true)
  end)
end

local function test_an_anchor_cycle_between_two_frames_is_reported_and_the_load_goes_on()
  local xml = [[<Ui>
<Frame name="CycA"><Anchors><Anchor point="TOP" relativeTo="CycB"/></Anchors></Frame>
<Frame name="CycB"><Anchors><Anchor point="TOP" relativeTo="CycA"/></Anchors></Frame>
<Frame name="After"/></Ui>]]
  withBrokenXml(xml, function(w, ns)
    A.eq(#w.errors, 1)
    A.eq(reportedAt(w, 2), 1) -- CycA's anchor is the one that closes the loop, when it settles
    A.eq(_G.After ~= nil, true)
    A.eq(ns.late, true)
  end)
end

local function test_a_template_inheriting_itself_through_another_is_reported_and_the_load_goes_on()
  local xml = [[<Ui>
<Frame name="IA" virtual="true" inherits="IB"/>
<Frame name="IB" virtual="true" inherits="IA"/>
<Frame name="UseIA" inherits="IA"/>
<Frame name="After"/></Ui>]]
  withBrokenXml(xml, function(w, ns)
    A.eq(#w.errors, 1)
    A.eq(reportedAt(w, 4), 1)
    A.contains(w.errors[1].message, "template 'IA' inherits itself")
    A.eq(_G.After ~= nil, true)
    A.eq(ns.late, true)
  end)
end

-- source: confirmed (row X27) UI.xsd types an <Anchor> point and relativePoint FRAMEPOINT and frameStrata FRAMESTRATA;
-- assumed: another value is reported at the element's line and ignored (the anchor is skipped, the strata stays the
-- default), the element and its children still build, and case is not checked.
local function test_a_bogus_anchor_point_or_frame_strata_is_reported_and_ignored_assumed()
  local xml = [[<Ui>
<Frame name="BadPoint"><Anchors><Anchor point="BOGUS"/><Anchor point="TOP" relativePoint="NOPE"/></Anchors></Frame>
<Frame name="BadStrata" frameStrata="BOGUS"><Frames><Frame name="BadStrataChild"/></Frames></Frame>
<Frame name="LowerOk" frameStrata="dialog"><Anchors><Anchor point="center"/></Anchors></Frame>
<Frame name="InheritOk" frameStrata="PARENT"/></Ui>]]
  withBrokenXml(xml, function(w, ns, info)
    A.same(w.errors, {})
    local report = table.concat(info.report, "\n")
    A.contains(report, "Ui.xml:2: <Anchor> point 'BOGUS' is not a FRAMEPOINT; anchor skipped")
    A.contains(report, "Ui.xml:2: <Anchor> relativePoint 'NOPE' is not a FRAMEPOINT; anchor skipped")
    A.contains(report, "Ui.xml:3: frameStrata 'BOGUS' is not a FRAMESTRATA; ignored")
    A.eq(report:find("dialog", 1, true) or report:find("center", 1, true) or report:find("PARENT", 1, true), nil)
    A.same({ _G.BadPoint:GetNumPoints(), _G.BadStrata:GetFrameStrata(), _G.LowerOk:GetNumPoints() }, { 0, "MEDIUM", 1 })
    A.eq(_G.BadStrataChild:GetParent(), _G.BadStrata)
    A.eq(ns.late, true)
  end)
end

-- Loads a temp addon XmlRoot whose TOC lists `listed` and whose other files are `files` (path -> text); returns ns, w.
local function loadTree(listed, files, fn)
  local root = Tmp.dir("addon") .. "/XmlRoot"
  fs.mkdirp(root)
  fs.writeFile(root .. "/XmlRoot.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\n" .. listed .. "\n")
  for path, text in pairs(files) do
    fs.mkdirp((root .. "/" .. path):match("^(.*)/[^/]*$"))
    fs.writeFile(root .. "/" .. path, text)
  end
  H.withFrameXML("retail", function(w)
    fn(Addon.load(w, { name = "XmlRoot", root = root }), w)
  end, { screen = SCREEN })
end

local function test_script_file_falls_back_to_the_addon_root_assumed()
  local files = {
    ["Sub/Ui.xml"] = '<Ui><Script file="Sub\\Code.lua"/><Include file="Sub\\More.xml"/></Ui>',
    ["Sub/Code.lua"] = "local _, ns = ...; ns.code = true",
    ["Sub/More.xml"] = '<Ui><Script file="Sub\\Deep.lua"/></Ui>',
    ["Sub/Deep.lua"] = "local _, ns = ...; ns.deep = true",
  }
  loadTree("Sub/Ui.xml", files, function(ns, w)
    A.same({ ns.code, ns.deep, #w.errors }, { true, true, 0 })
  end)
end

local function test_script_file_prefers_the_xml_folder_assumed()
  local files = {
    ["Sub/Ui.xml"] = '<Ui><Script file="Code.lua"/></Ui>',
    ["Sub/Code.lua"] = "local _, ns = ...; ns.where = 'sub'",
    ["Code.lua"] = "local _, ns = ...; ns.where = 'root'",
  }
  loadTree("Sub/Ui.xml", files, function(ns)
    A.eq(ns.where, "sub")
  end)
end

local function test_script_file_missing_from_both_places_is_still_reported_assumed()
  loadTree("Sub/Ui.xml", { ["Sub/Ui.xml"] = '<Ui><Script file="Gone.lua"/></Ui>' }, function(_, w)
    A.same({ #w.errors, tostring(w.errors[1].message) }, { 1, "addon:XmlRoot/Sub/Ui.xml lists missing file: addon:XmlRoot/Sub/Gone.lua" })
  end)
end

-- An <Include file> the XML names is reported against that XML file, not the TOC.
local function test_an_included_xml_that_is_missing_names_the_including_file()
  loadTree("Ui.xml", { ["Ui.xml"] = '<Ui><Include file="Gone.xml"/></Ui>' }, function(_, w)
    A.same({ #w.errors, tostring(w.errors[1].message) }, { 1, "addon:XmlRoot/Ui.xml lists missing file: addon:XmlRoot/Gone.xml" })
  end)
end

return function()
  test_script_file_falls_back_to_the_addon_root_assumed()
  test_script_file_prefers_the_xml_folder_assumed()
  test_script_file_missing_from_both_places_is_still_reported_assumed()
  test_an_included_xml_that_is_missing_names_the_including_file()
  test_a_bogus_anchor_point_or_frame_strata_is_reported_and_ignored_assumed()
  test_a_frame_anchored_to_itself_is_reported_and_the_load_goes_on()
  test_an_anchor_cycle_between_two_frames_is_reported_and_the_load_goes_on()
  test_a_template_inheriting_itself_through_another_is_reported_and_the_load_goes_on()
  test_xml_builds_at_its_toc_position()
end
