-- XML slider, status bar, scroll frame, edit box and button part elements and attributes: ThumbTexture, BarTexture,
-- ScrollChild, DisabledTexture, CheckedTexture, DisabledCheckedTexture, orientation, valueStep, fillStyle and the EditBox
-- attributes. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local H = require("tests.helpers.xml")

local function reportText(ctx)
  return table.concat(ctx.report, "\n")
end

local RANGE = [[
<Ui><Slider name="Sl" orientation="HORIZONTAL" valueStep="5"><ThumbTexture name="$parentThumb" file="Interface\Thumb"><Size x="9" y="11"/></ThumbTexture></Slider>
<StatusBar name="Bar" fillStyle="Center" orientation="VERTICAL"><BarTexture file="Interface\Bar"/></StatusBar>
<StatusBar name="Plain"/></Ui>]]

-- source: confirmed (W43) xsd:1034 and (W44) xsd:1004-1007: Slider and StatusBar take orientation, valueStep (Slider) and
-- fillStyle (StatusBar, spelled Standard, StandardNoRangeFill, Center or Reverse in the xsd, SetFillStyle takes upper case).
local function test_slider_and_status_bar_attributes_reach_their_setters() -- W43 W44
  H.withXml({ ["Ui.xml"] = RANGE }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Sl:GetOrientation(), _G.Sl:GetValueStep() }, { "HORIZONTAL", 5 })
    A.same({ _G.Bar:GetOrientation(), _G.Bar:GetFillStyle() }, { "VERTICAL", "CENTER" })
    A.eq(_G.Plain:GetFillStyle(), "STANDARD")
    A.eq(reportText(ctx), "")
  end)
end

local function test_thumb_and_bar_textures_become_the_widget_parts() -- W43 W44
  H.withXml({ ["Ui.xml"] = RANGE }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local thumb = _G.Sl:GetThumbTexture()
    A.same({ thumb, thumb:GetTexture(), thumb:GetWidth(), thumb:GetHeight() }, { _G.SlThumb, "Interface\\Thumb", 9, 11 })
    A.same({ _G.Bar:GetStatusBarTexture():GetTexture(), w.ui.state[thumb].widgetPart }, { "Interface\\Bar", "thumb" })
  end)
end

local SCROLL = [[
<Ui><ScrollFrame name="Sf"><Size x="100" y="50"/><Anchors><Anchor point="CENTER"/></Anchors><ScrollChild><Frame name="SfKid"><Size x="100" y="200"/><Anchors><Anchor point="TOPLEFT"/></Anchors></Frame></ScrollChild></ScrollFrame></Ui>]]

local function test_scroll_child_element_is_the_scroll_frames_child() -- W45
  H.withXml({ ["Ui.xml"] = SCROLL }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Sf:GetScrollChild(), _G.SfKid:GetParent(), _G.Sf:GetVerticalScrollRange() }, { _G.SfKid, _G.Sf, 150 })
    A.eq(reportText(ctx), "")
  end)
end

local EDIT = [[
<Ui><EditBox name="Eb" multiLine="true" numeric="true" maxLetters="7" autoFocus="false" historyLines="20" password="true"/>
<EditBox name="EbPlain"/></Ui>]]

local function test_edit_box_attributes_reach_their_setters() -- W35 W36 W37 W38 W39 W40
  H.withXml({ ["Ui.xml"] = EDIT }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local box = _G.Eb
    A.same(
      { box:IsMultiLine(), box:IsNumeric(), box:GetMaxLetters(), box:IsAutoFocus(), box:GetHistoryLines(), box:IsPassword() },
      { true, true, 7, false, 20, true }
    )
    A.same({ _G.EbPlain:IsMultiLine(), _G.EbPlain:IsAutoFocus(), _G.EbPlain:GetHistoryLines() }, { false, true, 0 })
    A.eq(reportText(ctx), "")
  end)
end

local BUTTONS = [[
<Ui><Button name="Bt"><DisabledTexture file="Interface\D"/></Button>
<CheckButton name="Cb"><CheckedTexture file="Interface\C"/><DisabledCheckedTexture file="Interface\DC"/></CheckButton></Ui>]]

local function test_disabled_and_checked_texture_elements_belong_to_the_button() -- W17
  H.withXml({ ["Ui.xml"] = BUTTONS }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same(
      { _G.Bt:GetDisabledTexture():GetTexture(), _G.Cb:GetCheckedTexture():GetTexture(), _G.Cb:GetDisabledCheckedTexture():GetTexture() },
      { "Interface\\D", "Interface\\C", "Interface\\DC" }
    )
    A.same({ _G.Bt:GetDisabledTexture():GetParent() == _G.Bt, reportText(ctx) }, { true, "" })
  end)
end

return function()
  test_slider_and_status_bar_attributes_reach_their_setters()
  test_thumb_and_bar_textures_become_the_widget_parts()
  test_scroll_child_element_is_the_scroll_frames_child()
  test_edit_box_attributes_reach_their_setters()
  test_disabled_and_checked_texture_elements_belong_to_the_button()
end
