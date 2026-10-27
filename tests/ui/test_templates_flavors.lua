-- The flavor and absence facts of the Phase 6 templates: HorizontalSliderTemplate on vanilla only, the retail panels'
-- lack BackdropTemplate, UnitFrameTemplate is absent. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local HW = require("tests.helpers.widgets")
local Templates = require("ui.templates")

local function test_horizontal_slider_exists_on_vanilla_only() -- W66
  HW.withWidgets("vanilla", function()
    local slider = _G.CreateFrame("Slider", nil, _G.UIParent, "HorizontalSliderTemplate")
    A.eq(slider:GetObjectType(), "Slider")
    A.eq(slider:GetOrientation(), "HORIZONTAL")
    A.eq(slider.Thumb:GetObjectType(), "Texture")
  end)
  for _, flavor in ipairs({ "retail", "forever" }) do
    HW.withWidgets(flavor, function(w)
      local slider = _G.CreateFrame("Slider", nil, _G.UIParent, "HorizontalSliderTemplate")
      A.eq(slider.Thumb, nil, flavor)
      A.eq(w.unscripted["template:HorizontalSliderTemplate"], 1, flavor)
    end)
  end
end

local function test_horizontal_slider_inherits_the_backdrop_template() -- W66
  HW.withWidgets("vanilla", function(w)
    local slider = _G.CreateFrame("Slider", nil, _G.UIParent, "HorizontalSliderTemplate")
    A.same(w.ui.state[slider].mixins, { "BackdropTemplateMixin" })
  end)
end

local function test_retail_panels_do_not_inherit_the_backdrop_template() -- W66
  HW.withWidgets("retail", function(w)
    for _, name in ipairs({ "DefaultPanelTemplate", "SimplePanelTemplate", "DialogBorderTemplate", "TooltipBorderBackdropTemplate" }) do
      local frame = _G.CreateFrame("Frame", nil, _G.UIParent, name)
      for _, mixin in ipairs(w.ui.state[frame].mixins) do
        A.truthy(mixin ~= "BackdropTemplateMixin", name)
      end
    end
  end)
end

local function test_a_flavor_gated_template_is_unknown_elsewhere() -- W66
  A.same(Templates.TEMPLATES.HorizontalSliderTemplate.flavors, { vanilla = true })
end

local function test_unit_frame_template_matches_w67() -- W67
  A.eq(Templates.TEMPLATES.UnitFrameTemplate, nil)
  HW.withWidgets("retail", function(w)
    _G.CreateFrame("Button", nil, _G.UIParent, "UnitFrameTemplate")
    A.eq(w.unscripted["template:UnitFrameTemplate"], 1)
  end)
end

local function test_unit_frame_template_is_absent_on_the_classic_flavors_assumed() -- W67
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "forever" }) do
    HW.withWidgets(flavor, function(w)
      _G.CreateFrame("Button", nil, _G.UIParent, "UnitFrameTemplate")
      A.eq(w.unscripted["template:UnitFrameTemplate"], 1, flavor)
    end)
  end
end

return function()
  test_horizontal_slider_exists_on_vanilla_only()
  test_horizontal_slider_inherits_the_backdrop_template()
  test_retail_panels_do_not_inherit_the_backdrop_template()
  test_a_flavor_gated_template_is_unknown_elsewhere()
  test_unit_frame_template_matches_w67()
  test_unit_frame_template_is_absent_on_the_classic_flavors_assumed()
end
