-- Core FrameXML fakes: UIParent, WorldFrame and the standard font objects.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_ui_parent_is_screen_sized_medium_strata_frame()
  withFrameXML("vanilla", function()
    A.same({ _G.UIParent:GetSize() }, { 1920, 1080 })
    A.eq(_G.UIParent:GetFrameStrata(), "MEDIUM")
  end)
end

local function test_world_frame_is_a_frame()
  withFrameXML("tbc", function()
    A.eq(_G.WorldFrame:GetObjectType(), "Frame")
  end)
end

local function test_font_objects_have_sizes()
  withFrameXML("mists", function()
    A.eq(select(2, _G.GameFontNormal:GetFont()), 12)
    A.eq(select(2, _G.GameTooltipHeaderText:GetFont()), 14)
    A.eq(select(2, _G.GameTooltipTextSmall:GetFont()), 10)
  end)
end

return function()
  test_ui_parent_is_screen_sized_medium_strata_frame()
  test_world_frame_is_a_frame()
  test_font_objects_have_sizes()
end
