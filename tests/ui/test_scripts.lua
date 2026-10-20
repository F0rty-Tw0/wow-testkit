-- Script handler support per widget type and flavor (Ketho WidgetAPI handlers, inherited).
local A = require("assert")
local Scripts = require("ui.scripts")

local function test_frame_supports_on_event()
  A.eq(Scripts.supports("Frame", "OnEvent", "retail"), true)
end

local function test_button_inherits_frame_scripts()
  A.eq(Scripts.supports("Button", "OnShow", "vanilla"), true)
  A.eq(Scripts.supports("Button", "OnClick", "vanilla"), true)
end

local function test_frame_lacks_button_scripts()
  A.eq(Scripts.supports("Frame", "OnClick", "retail"), false)
end

local function test_tooltip_set_unit_only_on_classic_flavors()
  A.eq(Scripts.supports("GameTooltip", "OnTooltipSetUnit", "retail"), false)
  A.eq(Scripts.supports("GameTooltip", "OnTooltipSetUnit", "forever"), false)
  A.eq(Scripts.supports("GameTooltip", "OnTooltipSetUnit", "vanilla"), true)
  A.eq(Scripts.supports("GameTooltip", "OnTooltipSetUnit", "tbc"), true)
  A.eq(Scripts.supports("GameTooltip", "OnTooltipSetUnit", "mists"), true)
end

local function test_unknown_type_supports_nothing()
  A.eq(Scripts.supports("NotAType", "OnEvent", "retail"), false)
end

return function()
  test_frame_supports_on_event()
  test_button_inherits_frame_scripts()
  test_frame_lacks_button_scripts()
  test_tooltip_set_unit_only_on_classic_flavors()
  test_unknown_type_supports_nothing()
end
