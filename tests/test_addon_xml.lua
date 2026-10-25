-- Loading an addon whose TOC lists an XML file: the XML builds at its TOC position, between the Lua files around it.
local A = require("assert")
local Addon = require("addon")
local H = require("tests.helpers.framexml")

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

return function()
  test_xml_builds_at_its_toc_position()
end
