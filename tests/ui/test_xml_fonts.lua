-- XML font objects: a root <Font> or <FontFamily> builds the global font object it names, virtual or not (row X34).
local A = require("assert")
local H = require("tests.helpers.xml")

local FONTS = [[
<Ui>
  <FontFamily name="FamSmall" virtual="true">
    <Member alphabet="korean"><Font font="Fonts\K.ttf" height="13"/></Member>
    <Member alphabet="roman"><Font font="Fonts\R.TTF" height="10" outline="NORMAL">
      <Shadow><Offset x="1" y="-1"/><Color r="0" g="0" b="0"/></Shadow></Font></Member>
  </FontFamily>
  <Font name="BaseFont" inherits="FamSmall" virtual="true"><Color r="1" g="0.82" b="0"/></Font>
  <Font name="GreyFont" inherits="BaseFont" justifyH="LEFT" virtual="true"><Color r="0.5" g="0.5" b="0.5"/></Font>
  <Font name="ThickFont" inherits="BaseFont" outline="THICK" height="14" virtual="true"/>
  <Font name="PlainFont" font="Fonts\P.TTF" virtual="true"><FontHeight val="9"/></Font>
  <Frame name="Holder"><Layers><Layer><FontString name="HolderText" inherits="GreyFont"/></Layer></Layers></Frame>
</Ui>]]

local function withFonts(fn)
  H.withXml({ ["Ui.xml"] = FONTS }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    fn(w, ctx)
  end)
end

local function test_a_virtual_font_is_a_global_font_object()
  withFonts(function()
    A.eq(_G.GreyFont:GetObjectType(), "Font")
    A.same({ _G.GreyFont:GetTextColor() }, { 0.5, 0.5, 0.5, 1 })
    A.eq(_G.GreyFont:GetJustifyH(), "LEFT")
  end)
end

local function test_a_font_family_is_its_roman_member_assumed()
  withFonts(function()
    A.same({ _G.FamSmall:GetFont() }, { "Fonts\\R.TTF", 10, "OUTLINE" })
    A.same({ _G.FamSmall:GetShadowOffset() }, { 1, -1 })
  end)
end

local function test_a_font_reads_what_it_does_not_set_through_inherits()
  withFonts(function()
    A.eq(_G.GreyFont:GetFontObject(), _G.BaseFont)
    A.same({ _G.GreyFont:GetFont() }, { "Fonts\\R.TTF", 10, "OUTLINE" })
  end)
end

local function test_outline_and_height_override_the_inherited_font_assumed()
  withFonts(function()
    A.same({ _G.ThickFont:GetFont() }, { "Fonts\\R.TTF", 14, "THICKOUTLINE" })
    A.same({ _G.PlainFont:GetFont() }, { "Fonts\\P.TTF", 9, "" })
  end)
end

-- source: forever 70862 compactunitframe.xml:31-32 FontStrings inherit GameFontDisable; compactunitframe.lua:1948-1952
-- multiplies the size GetFont returns.
local function test_a_font_string_inheriting_an_xml_font_has_its_size()
  withFonts(function()
    A.same({ _G.HolderText:GetFont() }, { "Fonts\\R.TTF", 10, "OUTLINE" })
  end)
end

local function test_a_font_inheriting_a_missing_font_is_reported()
  H.withXml({ ["Ui.xml"] = [[<Ui><Font name="Orphan" inherits="NoSuchFont" virtual="true"/></Ui>]] }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Orphan:GetFontObject(), nil)
    A.truthy(table.concat(ctx.report, "\n"):find("font object 'NoSuchFont' not found", 1, true))
  end)
end

return function()
  test_a_virtual_font_is_a_global_font_object()
  test_a_font_family_is_its_roman_member_assumed()
  test_a_font_reads_what_it_does_not_set_through_inherits()
  test_outline_and_height_override_the_inherited_font_assumed()
  test_a_font_string_inheriting_an_xml_font_has_its_size()
  test_a_font_inheriting_a_missing_font_is_reported()
end
