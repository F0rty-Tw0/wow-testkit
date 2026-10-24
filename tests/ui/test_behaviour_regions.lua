-- Region creation: CreateTexture and CreateFontString store the draw layer they were created in.
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets

local function test_a_texture_without_a_layer_is_artwork_sublevel_zero_assumed() -- (V8)
  withWidgets("retail", function(w)
    local texture = _G.CreateFrame("Frame"):CreateTexture()
    local layer, sublevel = texture:GetDrawLayer()
    A.eq(layer, "ARTWORK")
    A.eq(sublevel, 0)
    A.eq(w.unscripted["Texture:GetDrawLayer"], nil)
  end)
end

local function test_a_texture_keeps_the_layer_and_sublevel_it_was_created_with()
  withWidgets("retail", function()
    local texture = _G.CreateFrame("Frame"):CreateTexture("RegionTex", "OVERLAY", nil, 5)
    local layer, sublevel = texture:GetDrawLayer()
    A.eq(layer, "OVERLAY")
    A.eq(sublevel, 5)
    A.eq(_G.RegionTex, texture)
  end)
end

local function test_a_font_string_without_a_layer_is_artwork()
  withWidgets("retail", function()
    local fontString = _G.CreateFrame("Frame"):CreateFontString("RegionText", "BORDER")
    A.eq((fontString:GetDrawLayer()), "BORDER")
    A.eq((_G.CreateFrame("Frame"):CreateFontString():GetDrawLayer()), "ARTWORK")
  end)
end

return function()
  test_a_texture_without_a_layer_is_artwork_sublevel_zero_assumed()
  test_a_texture_keeps_the_layer_and_sublevel_it_was_created_with()
  test_a_font_string_without_a_layer_is_artwork()
end
