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

return function()
  test_animation_group_builds_with_its_attributes()
  test_offset_and_scale_attributes_reach_their_setters()
  test_an_xml_group_plays_by_its_orders_and_loops_assumed()
  test_unmapped_animation_attribute_is_reported()
  test_unknown_animation_type_is_reported_assumed()
end
