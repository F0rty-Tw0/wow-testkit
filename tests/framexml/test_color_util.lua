-- Colour objects and globals (framexml/fakes/color_util.lua). Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_font_colour_globals_have_the_recorded_values() -- W68
  withFrameXML("retail", function()
    A.same({ _G.NORMAL_FONT_COLOR:GetRGB() }, { 1, 0.824, 0 })
    A.same({ _G.HIGHLIGHT_FONT_COLOR:GetRGB() }, { 1, 1, 1 })
    A.same({ _G.WHITE_FONT_COLOR:GetRGB() }, { 1, 1, 1 })
    A.same({ _G.GRAY_FONT_COLOR:GetRGB() }, { 0.502, 0.502, 0.502 })
    A.same({ _G.LIGHTGRAY_FONT_COLOR:GetRGB() }, { 0.6, 0.6, 0.6 })
    A.same({ _G.GREEN_FONT_COLOR:GetRGB() }, { 0.098, 1, 0.098 })
    A.same({ _G.RED_FONT_COLOR:GetRGB() }, { 1, 0.125, 0.125 })
    A.same({ _G.YELLOW_FONT_COLOR:GetRGB() }, { 1, 1, 0 })
  end)
end

local function test_font_colour_hex_and_code_globals_match_the_literals() -- W68
  withFrameXML("retail", function()
    A.eq(_G.NORMAL_FONT_COLOR:GenerateHexColor(), "ffffd200")
    A.eq(_G.RED_FONT_COLOR:GenerateHexColor(), "ffff2020")
    A.eq(_G.GREEN_FONT_COLOR:GenerateHexColor(), "ff19ff19")
    A.eq(_G.NORMAL_FONT_COLOR_CODE, "|cffffd200")
    A.eq(_G.RED_FONT_COLOR:WrapTextInColorCode("x"), "|cffff2020x|r")
  end)
end

local function test_the_font_colours_come_from_the_ui_colour_table() -- W68
  withFrameXML("retail", function()
    local byTag = {}
    for _, entry in ipairs(_G.C_UIColor.GetColors()) do
      byTag[entry.baseTag] = entry.color
    end
    A.same({ byTag.NORMAL_FONT_COLOR.r, byTag.NORMAL_FONT_COLOR.g, byTag.NORMAL_FONT_COLOR.b, byTag.NORMAL_FONT_COLOR.a }, { 1, 0.824, 0, 1 })
    A.eq(byTag.GRAY_FONT_COLOR.r, _G.GRAY_FONT_COLOR.r)
  end)
end

local function test_the_font_colours_exist_on_every_flavor() -- W68
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "forever" }) do
    withFrameXML(flavor, function()
      A.eq(type(_G.NORMAL_FONT_COLOR.GetRGB), "function")
    end)
  end
end

local function test_create_color_and_wrap_text() -- W69
  withFrameXML("retail", function()
    local red = _G.CreateColor(1, 0, 0, 1)
    A.eq(red:WrapTextInColorCode("x"), "|cffff0000x|r")
    A.eq(_G.WrapTextInColorCode("x", "ff00ff00"), "|cff00ff00x|r")
    A.eq(_G.WrapTextInColor("x", red), "|cffff0000x|r")
    A.same({ _G.CreateColor(0.1, 0.2, 0.3):GetRGBA() }, { 0.1, 0.2, 0.3, 1 })
  end)
end

local function test_create_color_from_hex_string_reads_aarrggbb() -- W69
  withFrameXML("retail", function()
    A.same({ _G.CreateColorFromHexString("80FF0000"):GetRGBA() }, { 1, 0, 0, 128 / 255 })
  end)
end

local function test_a_hex_string_of_the_wrong_length_asserts_and_returns_nil() -- W69
  withFrameXML("retail", function(w)
    local seen
    w.errorHandler = function(message)
      seen = message
    end
    A.eq(_G.CreateColorFromHexString("FF0000"), nil)
    A.contains(seen, "AARRGGBB")
  end)
end

local function test_create_color_from_bytes_divides_by_255() -- W69
  withFrameXML("retail", function()
    A.same({ _G.CreateColorFromBytes(255, 0, 51, 255):GetRGBA() }, { 1, 0, 0.2, 1 })
    A.same({ _G.CreateColorFromBytes(255, 128, 0, 255):GetRGBAAsBytes() }, { 255, 128, 0, 255 })
  end)
end

local function test_color_methods_compare_set_and_format() -- W69
  withFrameXML("retail", function()
    local color = _G.CreateColor(1, 0, 0, 0.5)
    A.eq(color:IsEqualTo(_G.CreateColor(1, 0, 0, 0.5)), true)
    A.eq(color:IsEqualTo(_G.CreateColor(1, 0, 0, 1)), false)
    A.eq(color:IsRGBEqualTo(_G.CreateColor(1, 0, 0, 1)), true)
    color:SetRGB(0, 1, 0)
    A.same({ color:GetRGBA() }, { 0, 1, 0, 1 })
    A.eq(color:GenerateHexColorNoAlpha(), "00FF00")
    A.eq(color:GenerateHexColorMarkup(), "|cff00ff00")
  end)
end

local function test_get_class_colour_returns_the_class_rgb() -- W69
  withFrameXML("retail", function()
    local mage = _G.RAID_CLASS_COLORS.MAGE
    A.same({ _G.GetClassColor("MAGE") }, { mage.r, mage.g, mage.b, "ff3fc7eb" })
    A.same({ _G.GetClassColor("NOSUCHCLASS") }, { 1, 1, 1, "ffffffff" })
  end)
end

local function test_class_colours_are_colour_objects() -- W69
  withFrameXML("retail", function()
    local mage = _G.RAID_CLASS_COLORS.MAGE
    A.same({ mage:GetRGB() }, { mage.r, mage.g, mage.b })
    A.eq(mage:WrapTextInColorCode("m"), "|cff3fc7ebm|r")
    local api = _G.C_ClassColor.GetClassColor("MAGE")
    A.same({ api.r, api.g, api.b }, { mage.r, mage.g, mage.b })
    A.eq(_G.C_ClassColor.GetClassColor("NOSUCHCLASS"), nil)
  end)
end

local function test_standard_fonts_are_frizqt() -- W69
  withFrameXML("retail", function()
    A.eq(_G.STANDARD_TEXT_FONT, "Fonts\\FRIZQT__.TTF")
    A.eq(_G.UNIT_NAME_FONT, "Fonts\\FRIZQT__.TTF")
    A.eq(_G.DAMAGE_TEXT_FONT, "Fonts\\FRIZQT__.TTF")
  end)
end

-- Neither is a Blizzard global: CUSTOM_CLASS_COLORS comes from a colour addon, ColorGradient is in no extract or api list.
local function test_addon_made_globals_stay_absent() -- W69
  withFrameXML("retail", function()
    A.eq(_G.CUSTOM_CLASS_COLORS, nil)
    A.eq(_G.ColorGradient, nil)
  end)
end

return function()
  test_font_colour_globals_have_the_recorded_values()
  test_font_colour_hex_and_code_globals_match_the_literals()
  test_the_font_colours_come_from_the_ui_colour_table()
  test_the_font_colours_exist_on_every_flavor()
  test_create_color_and_wrap_text()
  test_create_color_from_hex_string_reads_aarrggbb()
  test_a_hex_string_of_the_wrong_length_asserts_and_returns_nil()
  test_create_color_from_bytes_divides_by_255()
  test_color_methods_compare_set_and_format()
  test_get_class_colour_returns_the_class_rgb()
  test_class_colours_are_colour_objects()
  test_standard_fonts_are_frizqt()
  test_addon_made_globals_stay_absent()
end
