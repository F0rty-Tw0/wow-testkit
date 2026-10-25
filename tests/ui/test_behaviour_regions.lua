-- Region creation: CreateTexture and CreateFontString store the draw layer they were created in.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HR = require("tests.helpers.render")
local HW = require("tests.helpers.widgets")
local Render = require("render")

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

local function test_a_font_string_template_applies_the_font_object_like_set_font_object()
  HF.withFrameXML("retail", function()
    local fontString = _G.CreateFrame("Frame"):CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    local path, size, flags = fontString:GetFont()
    A.same({ path, size, flags }, { "Fonts\\FRIZQT__.TTF", 10, "" })
    A.eq(fontString:GetFontObject(), _G.GameFontNormalSmall)
  end)
end

local function test_a_font_string_template_reaches_the_render_snapshot()
  HR.withRender(function(w)
    local host = _G.CreateFrame("Frame", "Host", _G.UIParent)
    host:SetSize(100, 100)
    host:SetPoint("CENTER")
    local fontString = host:CreateFontString("Templated", "ARTWORK", "GameTooltipHeaderText")
    fontString:SetPoint("CENTER")
    fontString:SetText("Hi")
    local item = HR.item(Render.snapshot(w), "Templated")
    A.eq(item.font, "font:fonts/frizqt__.ttf")
    A.eq(item.size, 14)
  end)
end

local function test_an_unknown_font_string_template_is_counted_and_adds_nothing()
  HF.withFrameXML("retail", function(w)
    local fontString = _G.CreateFrame("Frame"):CreateFontString(nil, "ARTWORK", "NoSuchFontObject")
    A.eq(fontString:GetFontObject(), nil)
    A.eq(w.unscripted["template:NoSuchFontObject"], 1)
  end)
end

local function test_a_font_string_template_that_is_not_a_font_object_adds_nothing()
  HF.withFrameXML("retail", function()
    local fontString = _G.CreateFrame("Frame"):CreateFontString(nil, "ARTWORK", "UIParent")
    A.eq(fontString:GetFontObject(), nil)
  end)
end

return function()
  test_a_font_string_template_applies_the_font_object_like_set_font_object()
  test_a_font_string_template_reaches_the_render_snapshot()
  test_an_unknown_font_string_template_is_counted_and_adds_nothing()
  test_a_font_string_template_that_is_not_a_font_object_adds_nothing()
  test_a_texture_without_a_layer_is_artwork_sublevel_zero_assumed()
  test_a_texture_keeps_the_layer_and_sublevel_it_was_created_with()
  test_a_font_string_without_a_layer_is_artwork()
end
