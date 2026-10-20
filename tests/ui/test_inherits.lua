-- Widget type -> doc systems, and the Ketho WidgetAPI inheritance walk.
local A = require("assert")
local Inherits = require("ui.inherits")
local Manifest = require("manifest")

local function test_frame_doc_systems_start_with_frame_api()
  local systems = Inherits.docSystemsFor("Frame")
  A.eq(systems[1], "SimpleFrameAPI")
  A.contains(systems, "SimpleFrameScriptObjectAPI")
end

local function test_unmapped_type_has_no_doc_systems()
  A.same(Inherits.docSystemsFor("Cooldown"), {})
end

local function test_ancestors_list_type_first_then_parents()
  local _, globals = Manifest.load("retail")
  local ancestors = Inherits.ancestors(globals.widgets, "CheckButton")
  A.eq(ancestors[1], "CheckButton")
  A.contains(ancestors, "Button")
  A.contains(ancestors, "Frame")
  A.contains(ancestors, "FrameScriptObject")
end

local function test_region_self_inherit_walks_script_region()
  local _, globals = Manifest.load("retail")
  A.contains(Inherits.ancestors(globals.widgets, "Texture"), "ScriptRegion")
end

local function test_method_names_follow_inherits()
  local _, globals = Manifest.load("retail")
  local names = Inherits.methodNames(globals.widgets, "Button")
  A.eq(names.SetPoint, true)
  A.eq(names.Click, true)
  A.eq(names.GetObjectType, true)
end

return function()
  test_frame_doc_systems_start_with_frame_api()
  test_unmapped_type_has_no_doc_systems()
  test_ancestors_list_type_first_then_parents()
  test_region_self_inherit_walks_script_region()
  test_method_names_follow_inherits()
end
