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

-- Loads an addon whose TOC lists Ui.xml (the given text) then Late.lua; returns the world, ns and the report in fn.
local function withBrokenXml(xml, fn)
  local root = Tmp.dir("addon") .. "/XmlBad"
  fs.mkdirp(root)
  fs.writeFile(root .. "/XmlBad.toc", "## Interface: " .. Flavors.get("retail").tocVersion .. "\n\nUi.xml\nLate.lua\n")
  fs.writeFile(root .. "/Ui.xml", xml)
  fs.writeFile(root .. "/Late.lua", "local _, ns = ...; ns.late = true")
  H.withFrameXML("retail", function(w)
    local ns = Addon.load(w, { name = "XmlBad", root = root })
    fn(w, ns)
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

return function()
  test_a_frame_anchored_to_itself_is_reported_and_the_load_goes_on()
  test_an_anchor_cycle_between_two_frames_is_reported_and_the_load_goes_on()
  test_a_template_inheriting_itself_through_another_is_reported_and_the_load_goes_on()
  test_xml_builds_at_its_toc_position()
end
