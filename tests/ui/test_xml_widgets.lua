-- XML button and font extras: state textures, ButtonText, FontHeight, Shadow, legacy Backdrop.
local A = require("assert")
local H = require("tests.helpers.xml")

local function reportText(ctx)
  return table.concat(ctx.report, "\n")
end

local BUTTON = [[
<Ui><Button name="Btn"><NormalTexture file="Interface\N"/><PushedTexture file="Interface\P"/><HighlightTexture file="Interface\H" alphaMode="ADD"/>
  <ButtonText name="$parentText"><FontHeight val="14"/><Shadow><Offset x="1" y="-1"/><Color r="0" g="0" b="0"/></Shadow></ButtonText></Button></Ui>]]

local function test_button_state_textures_belong_to_the_button()
  H.withXml({ ["Ui.xml"] = BUTTON }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local btn = _G.Btn
    A.same({ btn:GetNormalTexture():GetTexture(), btn:GetNormalTexture():GetParent() == btn }, { "Interface\\N", true })
    A.eq(btn:GetPushedTexture():GetTexture(), "Interface\\P")
    A.eq(btn:GetHighlightTexture():GetTexture(), "Interface\\H")
  end)
end

local function test_state_texture_alpha_mode_sets_the_blend_mode_assumed()
  H.withXml({ ["Ui.xml"] = BUTTON }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Btn:GetHighlightTexture():GetBlendMode(), "ADD")
  end)
end

local function test_state_texture_runs_its_own_children()
  local xml = [[
<Ui><Button name="Bt"><NormalTexture file="Interface\N"><Size x="12" y="14"/><TexCoords left="0" right="1" top="0" bottom="0.5"/></NormalTexture></Button></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local tex = _G.Bt:GetNormalTexture()
    A.same({ tex:GetWidth(), tex:GetHeight() }, { 12, 14 })
    A.same({ tex:GetTexCoord() }, { 0, 0, 0, 0.5, 1, 0, 1, 0.5 })
  end)
end

local function test_button_text_is_the_buttons_font_string_with_height_and_shadow()
  H.withXml({ ["Ui.xml"] = BUTTON }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local text = _G.BtnText
    A.eq(_G.Btn:GetFontString(), text)
    A.eq(text:GetObjectType(), "FontString")
    A.eq(w.ui.state[text].values.TextHeight[1], 14)
    A.same({ text:GetShadowOffset() }, { 1, -1 })
    A.same(w.ui.state[text].values.ShadowColor, { n = 4, 0, 0, 0, 1 })
  end)
end

local BACKDROP = [[
<Ui><Frame name="Bd" inherits="BackdropTemplate"><Backdrop bgFile="Interface\Bg" edgeFile="Interface\Edge" tile="true">
  <BackgroundInsets><AbsInset left="4" right="3" top="2" bottom="1"/></BackgroundInsets><TileSize><AbsValue val="16"/></TileSize>
  <EdgeSize><AbsValue val="12"/></EdgeSize></Backdrop></Frame>
<Frame name="Bare">
<Backdrop bgFile="x"/></Frame></Ui>]]

local function test_legacy_backdrop_fills_the_backdrop_info()
  H.withXml({ ["Ui.xml"] = BACKDROP }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local info = _G.Bd:GetBackdrop()
    A.same({ info.bgFile, info.edgeFile, info.tile, info.tileSize, info.edgeSize }, { "Interface\\Bg", "Interface\\Edge", true, 16, 12 })
    A.same({ info.insets.left, info.insets.right, info.insets.top, info.insets.bottom }, { 4, 3, 2, 1 })
  end)
end

local function test_legacy_backdrop_needs_the_backdrop_template()
  H.withXml({ ["Ui.xml"] = BACKDROP }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "Ui.xml:5: <Backdrop> needs BackdropTemplate; ignored")
  end)
end

return function()
  test_button_state_textures_belong_to_the_button()
  test_state_texture_alpha_mode_sets_the_blend_mode_assumed()
  test_state_texture_runs_its_own_children()
  test_button_text_is_the_buttons_font_string_with_height_and_shadow()
  test_legacy_backdrop_fills_the_backdrop_info()
  test_legacy_backdrop_needs_the_backdrop_template()
end
