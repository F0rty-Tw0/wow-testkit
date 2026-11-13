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
    A.eq(select(2, text:GetFont()), 14)
    A.same({ text:GetShadowOffset() }, { 1, -1 })
    A.same(w.ui.state[text].values.ShadowColor, { n = 4, 0, 0, 0, 1 })
  end)
end

-- forever blizzard_compactraidframemanager.xml:354 gives its tabs text="GROUPMANAGER_UNIT_MARKER" and the parent's OnLoad
-- (.lua:1339) reads tab:GetFontString():GetStringWidth(); the attribute was ignored on frames. (X39)
local function test_button_text_attribute_sets_the_text_assumed()
  local xml = [[
<Ui><Button name="TxA" text="TK_LABEL"/>
  <Button name="TxB" text="Plain"><ButtonText name="$parentText"/></Button></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    _G.TK_LABEL = "Label"
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.TxA:GetText(), _G.TxA:GetFontString():GetText() }, { "Label", "Label" })
    A.same({ _G.TxB:GetFontString() == _G.TxBText, _G.TxB:GetText() }, { true, "Plain" })
    local shown = 0
    for _, region in ipairs({ _G.TxB:GetRegions() }) do
      shown = shown + ((region:GetObjectType() == "FontString" and region:IsShown()) and 1 or 0)
    end
    A.eq(shown, 1, "the attribute's FontString steps aside for <ButtonText>'s")
    A.eq(reportText(ctx):find("'text'"), nil)
  end)
end

-- forever CRFManagerMarkerTabTemplate (blizzard_compactraidframemanager.xml:102-103) gives its tabs <NormalFont> and
-- <HighlightFont>; the kit reported them unsupported and the tabs kept no font objects. (X40)
local function test_state_font_elements_set_the_font_objects()
  local xml = [[
<Ui><Button name="TkFonts"><NormalFont style="TkNormal"/><HighlightFont style="TkHigh"/><DisabledFont style="TkOff"/></Button></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local fonts = {}
    for _, name in ipairs({ "TkNormal", "TkHigh", "TkOff" }) do
      fonts[name] = _G.CreateFont(name)
    end
    H.load(w, ctx, "Ui.xml")
    local b = _G.TkFonts
    A.same({ b:GetNormalFontObject(), b:GetHighlightFontObject(), b:GetDisabledFontObject() }, { fonts.TkNormal, fonts.TkHigh, fonts.TkOff })
    A.eq(reportText(ctx):find("Font>"), nil)
  end)
end

-- source: tbc 70577 blizzard_uipanels_game/classic/friendsframe.xml:183 declares a <Button> that inherits the
-- <CheckButton> ActionButtonTemplate (actionbuttontemplate.xml:149 has a <CheckedTexture>), and the live client loads
-- the friends frame. assumed: the part a Button has no setter for is skipped and the rest of the template still applies.
local MIXED = [[
<Ui><CheckButton name="CbTemplate" virtual="true"><NormalTexture file="Interface\N"/>
  <CheckedTexture file="Interface\C"/></CheckButton>
<Button name="Mixed" inherits="CbTemplate"/></Ui>]]

local function test_a_part_texture_the_widget_has_no_setter_for_is_skipped_assumed()
  H.withXml({ ["Ui.xml"] = MIXED }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local btn = _G.Mixed
    A.same({ btn:GetObjectType(), btn:GetNormalTexture():GetTexture() }, { "Button", "Interface\\N" })
    A.contains(reportText(ctx), "Ui.xml:2: Button has no SetCheckedTexture; <CheckedTexture> ignored")
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

-- The classic ItemButtonTemplate declares its icon with no Size and no Anchors (tbc itembuttontemplate.xml:10) and the
-- live client draws it filling the button (bag and loot icons).
local ANCHORLESS = [[
<Ui><Button name="IbTemplate" virtual="true"><Size x="37" y="37"/><Layers><Layer level="BORDER">
  <Texture name="$parentIconTexture" parentKey="icon"/>
  <Texture parentKey="Sized"><Size x="8" y="8"/></Texture>
  <Texture parentKey="Placed"><Anchors><Anchor point="CENTER"/></Anchors></Texture>
</Layer></Layers></Button></Ui>]]

local function withAnchorless(fn)
  H.withXml({ ["Ui.xml"] = ANCHORLESS }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local button = _G.CreateFrame("Button", "Ib", _G.UIParent, "IbTemplate")
    button:SetPoint("CENTER")
    fn(button)
  end)
end

local function test_a_texture_with_no_size_or_anchors_fills_its_frame_assumed() -- X28
  withAnchorless(function(button)
    local icon = button.icon
    A.same({ icon:GetLeft(), icon:GetTop(), icon:GetWidth(), icon:GetHeight() }, { button:GetLeft(), button:GetTop(), 37, 37 })
  end)
end

local function test_the_fill_stores_no_points_assumed() -- X28
  withAnchorless(function(button)
    A.same({ button.icon:GetNumPoints(), button.icon:GetPoint(1) }, { 0 })
  end)
end

local function test_a_texture_with_its_own_size_or_anchors_does_not_fill() -- X28
  withAnchorless(function(button)
    A.same({ button.Sized:GetNumPoints(), button.Placed:GetNumPoints() }, { 0, 1 })
    A.same({ button.Sized:GetWidth(), button.Sized:GetHeight() }, { 8, 8 })
  end)
end

local function test_lua_that_sizes_and_places_the_texture_replaces_the_fill_assumed() -- X28
  withAnchorless(function(button)
    local icon = button.icon
    icon:SetSize(10, 10)
    icon:SetPoint("CENTER")
    A.same({ icon:GetNumPoints(), icon:GetWidth(), icon:GetHeight() }, { 1, 10, 10 })
  end)
end

-- source: assumed (row X28) tbc 70577 blizzard_characterframe/cata/paperdollframe.xml:242-246 presses the anchorless
-- DeleteButton texture by moving its TOPLEFT alone.
local function test_a_texture_moved_by_one_point_keeps_the_frame_size_assumed() -- X28
  withAnchorless(function(button)
    local icon = button.icon
    icon:SetPoint("TOPLEFT", 1, -1)
    A.same({ icon:GetLeft(), icon:GetTop(), icon:GetWidth(), icon:GetHeight() }, { button:GetLeft() + 1, button:GetTop() - 1, 37, 37 })
  end)
end

return function()
  test_a_texture_with_no_size_or_anchors_fills_its_frame_assumed()
  test_the_fill_stores_no_points_assumed()
  test_a_texture_with_its_own_size_or_anchors_does_not_fill()
  test_lua_that_sizes_and_places_the_texture_replaces_the_fill_assumed()
  test_a_texture_moved_by_one_point_keeps_the_frame_size_assumed()
  test_button_state_textures_belong_to_the_button()
  test_state_texture_alpha_mode_sets_the_blend_mode_assumed()
  test_state_texture_runs_its_own_children()
  test_a_part_texture_the_widget_has_no_setter_for_is_skipped_assumed()
  test_button_text_is_the_buttons_font_string_with_height_and_shadow()
  test_button_text_attribute_sets_the_text_assumed()
  test_state_font_elements_set_the_font_objects()
  test_legacy_backdrop_fills_the_backdrop_info()
  test_legacy_backdrop_needs_the_backdrop_template()
end
