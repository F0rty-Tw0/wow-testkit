-- XML layout elements: Size, Anchors (with deferred targets), Layers, KeyValues, Color and TexCoords.
local A = require("assert")
local H = require("tests.helpers.xml")

local function reportText(ctx)
  return table.concat(ctx.report, "\n")
end

local function rect(name)
  return { _G[name]:GetRect() }
end

local PAIR = [[
<Ui>
  <Frame name="Pa"><Size x="200" y="100"/>
    <Anchors><Anchor point="TOPLEFT" relativeTo="UIParent" x="10" y="-20"/></Anchors></Frame>
  <Frame name="Pb"><Size><AbsDimension x="30" y="30"/></Size>
    <Anchors><Anchor point="TOPLEFT" relativeTo="Pa" relativePoint="BOTTOMLEFT"><Offset><AbsDimension x="0" y="-10"/></Offset></Anchor></Anchors></Frame>
</Ui>]]

local function test_size_and_anchors_give_the_hand_computed_rects()
  H.withXml({ ["Ui.xml"] = PAIR }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- Pa: top = 800 - 20 = 780, bottom = 780 - 100 = 680, left = 10.
    A.same(rect("Pa"), { 10, 680, 200, 100 })
    -- Pb: top = Pa bottom - 10 = 670, bottom = 670 - 30 = 640, left = 10.
    A.same(rect("Pb"), { 10, 640, 30, 30 })
  end)
end

local function test_anchor_without_a_target_on_a_parentless_frame_uses_the_screen_assumed()
  local xml = '<Ui><Frame name="Pa"><Size x="200" y="100"/><Anchors><Anchor point="TOPLEFT" x="10" y="-20"/></Anchors></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- The screen is 1000x800: top = 800 - 20 = 780, bottom = 780 - 100 = 680, left = 10.
    A.same(rect("Pa"), { 10, 680, 200, 100 })
  end)
end

local function test_parent_forms_and_set_all_points()
  local xml = [[
<Ui><Frame name="Par"><Size x="200" y="100"/><Anchors><Anchor point="TOPLEFT" relativeTo="UIParent" x="10" y="-20"/></Anchors>
  <Frames>
    <Frame name="$parentKid"><Size x="20" y="20"/>
      <Anchors><Anchor point="BOTTOMRIGHT" relativeTo="$parent" relativePoint="BOTTOMRIGHT"/></Anchors></Frame>
    <Frame name="$parentFill" setAllPoints="true"/>
  </Frames></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- Par spans x 10..210, y 680..780. Kid's right edge is 210 and its bottom 680, so left = 190.
    A.same(rect("ParKid"), { 190, 680, 20, 20 })
    A.same(rect("ParFill"), rect("Par"))
  end)
end

-- source: wiki XML/Anchor, relativeTo "Another widget to align against (in `_G`)"; row X8 (`$parentKid` forms)
local function test_relative_to_substitutes_a_parent_name_that_holds_a_percent_sign()
  local xml = [[
<Ui><Frame name="Pct%Bar"><Size x="200" y="100"/><Anchors><Anchor point="TOPLEFT" relativeTo="UIParent" x="10" y="-20"/></Anchors>
  <Frames>
    <Frame name="$parentKid"><Size x="20" y="20"/><Anchors><Anchor point="TOPLEFT"/></Anchors></Frame>
    <Frame name="$parentOther"><Size x="20" y="20"/>
      <Anchors><Anchor point="TOPLEFT" relativeTo="$parentKid" relativePoint="BOTTOMLEFT"/></Anchors></Frame>
  </Frames></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- Kid sits at Pct%Bar's top left (10, 780); Other hangs below it: top 760, bottom 740.
    A.same(rect("Pct%BarOther"), { 10, 740, 20, 20 })
  end)
end

local function test_anchor_without_a_target_on_a_nested_frame_uses_the_parent_assumed()
  local xml = [[
<Ui><Frame name="Par"><Size x="200" y="100"/><Anchors><Anchor point="TOPLEFT" relativeTo="UIParent" x="10" y="-20"/></Anchors>
  <Frames><Frame name="$parentKid"><Size x="20" y="20"/><Anchors><Anchor point="TOPLEFT" x="5" y="-5"/></Anchors></Frame></Frames>
</Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- Par's top left is (10, 780); Kid's is 5 right and 5 down from it: left 15, top 775, bottom 755.
    A.same(rect("ParKid"), { 15, 755, 20, 20 })
  end)
end

local function test_layer_region_anchors_to_a_frame_declared_after_it()
  local xml = [[
<Ui><Frame name="Hold"><Size x="100" y="100"/><Anchors><Anchor point="BOTTOMLEFT" relativeTo="UIParent"/></Anchors>
  <Layers><Layer><Texture parentKey="Tex"><Size x="10" y="10"/>
    <Anchors><Anchor point="LEFT" relativeKey="$parent.B" relativePoint="RIGHT"/></Anchors></Texture></Layer></Layers>
  <Frames><Frame name="HoldB" parentKey="B"><Size x="40" y="40"/>
    <Anchors><Anchor point="TOPLEFT" relativeTo="$parent"/></Anchors></Frame></Frames></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- Hold spans x 0..100, y 0..100, so B spans x 0..40, y 60..100 (centre y 80). Tex's left is B's right edge, 40, and
    -- its middle sits at y 80: bottom = 80 - 5 = 75.
    A.same({ _G.Hold.Tex:GetRect() }, { 40, 75, 10, 10 })
  end)
end

local function test_relative_key_may_name_a_sibling_frame_built_later_assumed()
  local xml = [[
<Ui><Frame name="Hold"><Size x="100" y="100"/><Anchors><Anchor point="BOTTOMLEFT" relativeTo="UIParent"/></Anchors>
  <Frames>
    <Frame name="HoldA"><Size x="10" y="10"/>
      <Anchors><Anchor point="LEFT" relativeKey="$parent.B" relativePoint="RIGHT"/></Anchors></Frame>
    <Frame name="HoldB" parentKey="B"><Size x="40" y="40"/><Anchors><Anchor point="TOPLEFT" relativeTo="$parent"/></Anchors></Frame>
  </Frames></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- HoldB spans x 0..40 (TOPLEFT of Hold: left 0, top 100), so HoldA's left is 40.
    A.eq(rect("HoldA")[1], 40)
  end)
end

local function test_relative_key_walks_two_levels_assumed()
  local xml = [[
<Ui><Frame name="Hold"><Size x="100" y="100"/><Anchors><Anchor point="BOTTOMLEFT" relativeTo="UIParent"/></Anchors>
  <Frames>
    <Frame name="HoldA" parentKey="A"><Size x="30" y="30"/><Anchors><Anchor point="TOPLEFT" relativeTo="$parent"/></Anchors>
      <Frames><Frame name="$parentB" parentKey="B"><Size x="40" y="40"/>
        <Anchors><Anchor point="TOPLEFT" relativeTo="$parent"/></Anchors></Frame></Frames></Frame>
    <Frame name="HoldC"><Size x="10" y="10"/>
      <Anchors><Anchor point="LEFT" relativeKey="$parent.A.B" relativePoint="RIGHT"/></Anchors></Frame>
  </Frames></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- A's top left is Hold's (0, 100); B hangs from it at x 0..40, so C's left is 40.
    A.eq(rect("HoldC")[1], 40)
  end)
end

local function test_missing_anchor_target_is_reported_and_skipped_assumed()
  local xml = '<Ui>\n<Frame name="Lost"><Anchors><Anchor point="TOP" relativeTo="Nope"/></Anchors></Frame>\n</Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "Ui.xml:2: anchor target 'Nope' not found; anchor skipped")
    A.eq(_G.Lost:GetNumPoints(), 0)
  end)
end

local function test_deferred_anchor_resolves_once_its_target_is_built_assumed()
  local xml = [[
<Ui>
  <Frame name="Fa"><Size x="10" y="10"/><Anchors><Anchor point="LEFT" relativeTo="Fb"/></Anchors></Frame>
  <Frame name="Fb"><Size x="20" y="20"/><Anchors><Anchor point="CENTER" relativeTo="UIParent"/></Anchors></Frame>
</Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- Fb is centred on the 1000-wide screen, so it spans x 490..510; Fa's LEFT sits on Fb's LEFT: 490.
    A.eq(_G.Fa:GetLeft(), 490)
    A.eq(reportText(ctx), "")
  end)
end

local function test_own_size_attributes_set_only_their_axis()
  local xml = '<Ui><Frame name="Sz"><Size x="10" y="10"/><Size x="30"/></Frame><Frame name="Sz2"><Size y="7"/></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Sz:GetSize() }, { 30, 10 })
    A.same({ _G.Sz2:GetHeight(), _G.Sz2:GetWidth() }, { 7, 0 })
  end)
end

local function test_rel_dimension_is_reported_and_ignored()
  local xml = '<Ui><Frame name="Rel"><Size><RelDimension x="0.5" y="0.5"/></Size></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "<RelDimension> is not modelled; ignored")
    A.same({ _G.Rel:GetSize() }, { 0, 0 })
  end)
end

local function test_second_anchors_element_replaces_the_first_assumed()
  local xml = [[
<Ui><Frame name="Two"><Size x="5" y="5"/>
  <Anchors><Anchor point="TOPLEFT"/></Anchors>
  <Anchors><Anchor point="BOTTOMRIGHT"/></Anchors></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Two:GetNumPoints(), (_G.Two:GetPoint(1)) }, { 1, "BOTTOMRIGHT" })
  end)
end

local function test_second_anchors_element_drops_the_first_ones_waiting_anchors_assumed()
  local xml = [[
<Ui><Frame name="Dr"><Size x="5" y="5"/>
  <Anchors><Anchor point="TOP" relativeTo="Nope"/></Anchors>
  <Anchors><Anchor point="BOTTOM"/></Anchors></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Dr:GetNumPoints(), (_G.Dr:GetPoint(1)) }, { 1, "BOTTOM" })
    A.eq(reportText(ctx), "")
  end)
end

local LAYERS = [[
<Ui><Frame name="Lay"><Size x="50" y="50"/><Anchors><Anchor point="CENTER" relativeTo="UIParent"/></Anchors>
  <Layers>
    <Layer level="BACKGROUND" textureSubLevel="-1"><Texture parentKey="Bg" setAllPoints="true"><Color r="1" g="0" b="0" a="0.5"/><TexCoords left="0" right="0.5" top="0" bottom="1"/></Texture></Layer>
    <Layer><Texture parentKey="Mid"><Color r="0" g="1" b="0"/></Texture></Layer>
    <Layer level="OVERLAY"><FontString parentKey="Label" text="Hi"><Color r="1" g="1" b="0"/></FontString></Layer>
  </Layers></Frame></Ui>]]

local function test_layers_give_regions_their_draw_layer_and_texcoords()
  H.withXml({ ["Ui.xml"] = LAYERS }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local lay = _G.Lay
    A.same({ lay.Bg:GetDrawLayer() }, { "BACKGROUND", -1 })
    A.same({ lay.Mid:GetDrawLayer() }, { "ARTWORK", 0 })
    A.same({ lay.Label:GetDrawLayer() }, { "OVERLAY", 0 })
    A.same(w.ui.state[lay.Bg].values.TexCoord, { n = 4, 0, 0.5, 0, 1 })
  end)
end

local function test_color_calls_the_setter_of_its_region_assumed()
  H.withXml({ ["Ui.xml"] = LAYERS }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local lay = _G.Lay
    A.same(w.ui.state[lay.Bg].values.ColorTexture, { n = 4, 1, 0, 0, 0.5 })
    -- alpha defaults to 1 (X18)
    A.same(w.ui.state[lay.Mid].values.ColorTexture, { n = 4, 0, 1, 0, 1 })
    A.same({ lay.Label:GetTextColor() }, { 1, 1, 0, 1 })
  end)
end

local function test_keyvalues_set_string_number_and_boolean()
  local xml = [[
<Ui><Frame name="Kv"><KeyValues>
  <KeyValue key="n" value="3" type="number"/><KeyValue key="s" value="x"/><KeyValue key="b" value="true" type="boolean"/>
</KeyValues></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Kv.n, _G.Kv.s, _G.Kv.b }, { 3, "x", true })
  end)
end

local function test_global_keyvalue_stores_the_global_assumed()
  local xml = '<Ui><Frame name="Kg"><KeyValues><KeyValue key="g" value="Foo" type="global"/></KeyValues></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local foo = { 1 }
    w:setGlobal("Foo", foo)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Kg.g, foo)
  end)
end

local function test_keyvalue_types_follow_the_schema_conversions()
  local xml = [[
<Ui><Frame name="Kt"><KeyValues>
  <KeyValue key="a" value="1" type="nil"/><KeyValue key="b" value="0" type="boolean"/><KeyValue key="c" value="on" type="boolean"/>
  <KeyValue key="d" value="two" type="number"/><KeyValue key="e" value="v" type="local"/><KeyValue key="f" value="v" type="local"/>
</KeyValues></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local kt = _G.Kt
    A.same({ kt.a, kt.b, kt.c, kt.d, kt.e }, { nil, false, true, 0, nil })
    local text = reportText(ctx)
    A.contains(text, "KeyValue type 'local' ignored")
    A.eq(select(2, text:gsub("KeyValue type 'local' ignored", "")), 1)
  end)
end

local function test_keyvalues_apply_before_the_other_child_elements_assumed()
  local xml = [[
<Ui><Frame name="Ko"><Layers><Layer><Texture parentKey="X"/></Layer></Layers>
  <KeyValues><KeyValue key="X" value="kv"/></KeyValues></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- KeyValues ran first, so the Texture's parentKey wrote last.
    A.eq(_G.Ko.X:GetObjectType(), "Texture")
  end)
end

return function()
  test_size_and_anchors_give_the_hand_computed_rects()
  test_anchor_without_a_target_on_a_parentless_frame_uses_the_screen_assumed()
  test_parent_forms_and_set_all_points()
  test_anchor_without_a_target_on_a_nested_frame_uses_the_parent_assumed()
  test_relative_to_substitutes_a_parent_name_that_holds_a_percent_sign()
  test_layer_region_anchors_to_a_frame_declared_after_it()
  test_relative_key_may_name_a_sibling_frame_built_later_assumed()
  test_relative_key_walks_two_levels_assumed()
  test_missing_anchor_target_is_reported_and_skipped_assumed()
  test_deferred_anchor_resolves_once_its_target_is_built_assumed()
  test_own_size_attributes_set_only_their_axis()
  test_rel_dimension_is_reported_and_ignored()
  test_second_anchors_element_replaces_the_first_assumed()
  test_second_anchors_element_drops_the_first_ones_waiting_anchors_assumed()
  test_layers_give_regions_their_draw_layer_and_texcoords()
  test_color_calls_the_setter_of_its_region_assumed()
  test_keyvalues_set_string_number_and_boolean()
  test_global_keyvalue_stores_the_global_assumed()
  test_keyvalue_types_follow_the_schema_conversions()
  test_keyvalues_apply_before_the_other_child_elements_assumed()
end
