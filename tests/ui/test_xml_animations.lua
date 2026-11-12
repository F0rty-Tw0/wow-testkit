-- XML <Animations>: animation groups and animations built with their attributes; nothing plays.
local A = require("assert")
local H = require("tests.helpers.xml")

local function reportText(ctx)
  return table.concat(ctx.report, "\n")
end

local GLOW = [[
<Ui><Frame name="Glow"><Animations><AnimationGroup name="$parentPulse" parentKey="Pulse" looping="BOUNCE" setToFinalAlpha="true">
  <Alpha parentKey="Fade" duration="0.5" fromAlpha="1" toAlpha="0" order="1"/>
  <Translation parentKey="Slide" offsetX="10" duration="0.25" order="2" bogus="1"/>
  <Scale parentKey="Grow" scaleX="2" startDelay="0.1"/></AnimationGroup></Animations></Frame></Ui>]]

local function test_animation_group_builds_with_its_attributes()
  H.withXml({ ["Ui.xml"] = GLOW }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local group = _G.Glow.Pulse
    A.eq(_G.GlowPulse, group)
    A.eq(group:GetLooping(), "BOUNCE")
    A.eq(group:IsSetToFinalAlpha(), true)
    A.eq(select("#", group:GetAnimations()), 3)
    A.same(
      { group.Fade:GetObjectType(), group.Fade:GetDuration(), group.Fade:GetFromAlpha(), group.Fade:GetToAlpha(), group.Fade:GetOrder() },
      { "Alpha", 0.5, 1, 0, 1 }
    )
  end)
end

local function test_offset_and_scale_attributes_reach_their_setters()
  H.withXml({ ["Ui.xml"] = GLOW }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local group = _G.Glow.Pulse
    A.same({ group.Slide:GetOffset() }, { 10, 0 })
    -- scaleX alone: Scale:SetScale(2, 1) sets the factor the animation ends at (the y factor stays 1)
    A.same({ group.Grow:GetScale() }, { 2, 1 })
    A.eq(group.Grow:GetStartDelay(), 0.1)
  end)
end

local function test_an_xml_group_plays_by_its_orders_and_loops_assumed()
  H.withXml({ ["Ui.xml"] = GLOW }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local group = _G.Glow.Pulse
    group:Play()
    w:advance(0.5)
    A.same({ group.Fade:GetProgress(), group.Slide:GetProgress(), group.Fade:GetTarget() == _G.Glow }, { 1, 0, true })
    w:advance(0.25)
    A.same({ group:IsPlaying(), group.Slide:GetProgress() }, { true, 1 })
    -- 0.75 long (the Scale element is order 1, 0.1 delay): the BOUNCE group turns instead of finishing
    w:advance(0.25)
    A.same({ group:IsPlaying(), group:IsDone() }, { true, false })
  end)
end

-- source: W82 ActionButtonSpellAlerts.xml:22 writes a FlipBook with flipBookRows, flipBookColumns, flipBookFrames,
-- flipBookFrameWidth and flipBookFrameHeight.
local function test_flipbook_attributes_reach_their_setters()
  local xml = '<Ui><Frame name="Fb"><Animations><AnimationGroup parentKey="G"><FlipBook parentKey="Flip" flipBookRows="6"'
    .. ' flipBookColumns="5" flipBookFrames="30" flipBookFrameWidth="0" flipBookFrameHeight="0"/></AnimationGroup>'
    .. '</Animations></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local flip = _G.Fb.G.Flip
    A.same(
      { flip:GetFlipBookRows(), flip:GetFlipBookColumns(), flip:GetFlipBookFrames(), flip:GetFlipBookFrameWidth() },
      { 6, 5, 30, 0 }
    )
    A.eq(reportText(ctx):find("ignored", 1, true), nil)
  end)
end

local function test_unmapped_animation_attribute_is_reported()
  H.withXml({ ["Ui.xml"] = GLOW }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "Ui.xml:3: <Translation> attribute 'bogus' ignored")
  end)
end

local function test_unknown_animation_type_is_reported_assumed()
  local xml = '<Ui><Frame name="Wb"><Animations><AnimationGroup parentKey="G">\n<Wobble/></AnimationGroup></Animations></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "Ui.xml:2: unknown animation type 'Wobble'; ignored")
    A.eq(select("#", _G.Wb.G:GetAnimations()), 0)
  end)
end

-- source: row X35, forever 70862 blizzard_buffframe/buffframetemplates.xml:64-66 (a virtual AnimationGroup with a mixin
-- and an <Animation parentKey="Animation"/>), :82 (a group inheriting it), buffframe.lua:66 (calls the mixin's Init).
local FADER = [[
<Ui>
  <AnimationGroup name="FaderT" mixin="FaderMixin" looping="BOUNCE" virtual="true">
    <Animation parentKey="Animation" duration="2"/>
    <Scripts><OnPlay method="OnPlay"/></Scripts>
  </AnimationGroup>
  <Frame name="Holder"><Animations><AnimationGroup parentKey="Fader" inherits="FaderT" setToFinalAlpha="true"/></Animations></Frame>
</Ui>]]

local function test_an_animation_group_inherits_a_virtual_group_template()
  H.withXml({ ["Ui.xml"] = FADER }, function(w, ctx)
    _G.FaderMixin = {
      Init = function() end,
      OnPlay = function(self)
        self.played = true
      end,
    }
    H.load(w, ctx, "Ui.xml")
    local fader = _G.Holder.Fader
    A.eq(fader.Init, _G.FaderMixin.Init)
    A.same({ fader:GetLooping(), fader:IsSetToFinalAlpha() }, { "BOUNCE", true })
    A.same({ fader.Animation:GetObjectType(), fader.Animation:GetDuration() }, { "Animation", 2 })
    fader:Play()
    A.eq(fader.played, true)
    A.eq(_G.FaderT, nil)
  end)
end

local function test_an_unknown_group_template_is_reported()
  local xml = [[<Ui><Frame name="Hd"><Animations><AnimationGroup parentKey="G" inherits="NoSuchGroupT"/></Animations></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "animation group template 'NoSuchGroupT' not found")
    A.truthy(_G.Hd.G)
  end)
end

return function()
  test_an_animation_group_inherits_a_virtual_group_template()
  test_an_unknown_group_template_is_reported()
  test_animation_group_builds_with_its_attributes()
  test_offset_and_scale_attributes_reach_their_setters()
  test_an_xml_group_plays_by_its_orders_and_loops_assumed()
  test_flipbook_attributes_reach_their_setters()
  test_unmapped_animation_attribute_is_reported()
  test_unknown_animation_type_is_reported_assumed()
end
