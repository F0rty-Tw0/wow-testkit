-- XML virtual templates: registration, CreateFrame and inherits integration, per-axis size, anchors and script hooks.
local A = require("assert")
local H = require("tests.helpers.xml")
local Xml = require("ui.xml")
local XmlBuild = require("ui.xml_build")
local XmlParse = require("ui.xml_parse")

local TPL = [[
<Ui>
  <Frame name="BoxT" virtual="true"><Size x="120" y="40"/>
    <Layers><Layer><FontString parentKey="Title" text="T"/></Layer></Layers>
    <Frames><Button name="$parentOk" parentKey="Ok"/></Frames>
    <Scripts><OnLoad>Mark("T")</OnLoad></Scripts>
  </Frame>
</Ui>]]

local function logTo(w)
  local log = {}
  w:setGlobal("Mark", function(x)
    log[#log + 1] = x
  end)
  return log
end

local function test_virtual_template_builds_through_createframe() -- (X14)
  H.withXml({ ["Ui.xml"] = TPL }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    local f = _G.CreateFrame("Frame", "Z", _G.UIParent, "BoxT")
    A.same({ f:GetSize() }, { 120, 40 })
    A.same({ f.Title:GetText(), f.Ok:GetObjectType(), _G.ZOk == f.Ok }, { "T", "Button", true })
    A.same(log, { "T" }) -- OnLoad ran once, before CreateFrame returned
  end)
end

local function test_virtual_element_builds_no_frame_and_no_global()
  H.withXml({ ["Ui.xml"] = TPL }, function(w, ctx)
    logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.BoxT, nil)
    A.eq(_G.BoxTOk, nil)
    A.eq(w.ui.virtuals.BoxT.type, "Frame")
  end)
end

local function test_on_load_runs_once_when_an_xml_element_inherits_a_virtual()
  local xml = TPL:gsub("</Ui>", '<Frame name="Own" inherits="BoxT"/></Ui>')
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    local log = logTo(w)
    H.load(w, ctx, "Ui.xml")
    A.same(log, { "T" })
    A.same({ _G.Own:GetSize() }, { 120, 40 })
    A.eq(_G.Own.Ok, _G.OwnOk)
  end)
end

local function test_script_error_of_a_virtual_names_the_xml_file_and_line()
  local xml = '<Ui>\n<Frame name="Er" virtual="true"><Scripts>\n<OnLoad>error("bad")</OnLoad></Scripts></Frame></Ui>'
  H.withXml({ ["Dir/Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Dir/Ui.xml")
    _G.CreateFrame("Frame", nil, nil, "Er")
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "addon:XmlT/Dir/Ui.xml:3:")
  end)
end

local function test_nested_virtual_frame_registers_too()
  local xml = '<Ui><Frame name="Host"><Frames><Frame name="InnerT" virtual="true"><Size x="3" y="4"/></Frame></Frames></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.InnerT, nil)
    A.same({ _G.CreateFrame("Frame", nil, nil, "InnerT"):GetSize() }, { 3, 4 })
  end)
end

local function test_virtual_without_a_name_is_reported_and_skipped()
  H.withXml({ ["Ui.xml"] = '<Ui>\n<Frame virtual="true"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(table.concat(ctx.report, "\n"), "Ui.xml:2: virtual <Frame> needs a name; ignored")
    A.eq(next(w.ui.virtuals), nil)
  end)
end

local CHAIN = [[
<Ui>
  <Frame name="T1" virtual="true"><Size x="10" y="10"/></Frame>
  <Frame name="T2" virtual="true" inherits="T1"><Size x="20"/></Frame>
  <Frame name="Own" inherits="T2"><Size y="30"/></Frame>
</Ui>]]

-- source: wiki XML/LayoutFrame, `inherits` "Inherits a comma-separated list of XML virtual templates" (row X4)
local function test_inherited_template_chain_and_own_size_merge_per_axis_assumed()
  H.withXml({ ["Ui.xml"] = CHAIN }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    -- T1 gives 10x10, T2 overrides the width (20), Own overrides the height (30).
    A.same({ _G.Own:GetSize() }, { 20, 30 })
  end)
end

local function test_inherits_list_applies_in_order_and_the_last_template_wins_assumed()
  local xml = '<Ui><Frame name="Ta" virtual="true"><Size x="1" y="1"/></Frame><Frame name="Tb" virtual="true"><Size x="2"/></Frame>'
    .. '<Frame name="Ab" inherits="Ta, Tb"/><Frame name="Ba" inherits="Tb,Ta"/></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Ab:GetSize() }, { 2, 1 })
    A.same({ _G.Ba:GetSize() }, { 1, 1 })
  end)
end

-- Runs a Button that inherits a template with an OnClick, its own OnClick carrying `attr`; returns the log after a click.
local function clickLog(attr)
  local out
  local xml = '<Ui><Button name="BtT" virtual="true"><Scripts><OnClick>Mark("T")</OnClick></Scripts></Button>'
    .. '<Button name="Sc" inherits="BtT"><Scripts><OnClick'
    .. attr
    .. '>Mark("E")</OnClick></Scripts></Button></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    out = logTo(w)
    H.load(w, ctx, "Ui.xml")
    w:callScript(_G.Sc, "OnClick", "LeftButton", false)
  end)
  return out
end

local function test_script_without_inherit_replaces_the_template_one_assumed()
  A.same(clickLog(""), { "E" })
  A.same(clickLog(' inherit="none"'), { "E" })
end

-- source: wiki XML/Scripts, `inherit` "Hooks (prepend, append) other scripts inherited through an XML virtual template"
local function test_script_inherit_hooks_the_template_script()
  for _, mode in ipairs({ "prepend", "append" }) do
    local log = clickLog(' inherit="' .. mode .. '"')
    table.sort(log)
    A.same(log, { "E", "T" })
  end
end

local function test_script_inherit_prepend_and_append_order_assumed()
  A.same(clickLog(' inherit="prepend"'), { "E", "T" })
  A.same(clickLog(' inherit="append"'), { "T", "E" })
end

local function test_register_virtual_directly()
  H.withXml({}, function(w, ctx)
    local node = XmlParse.parse('<Frame virtual="true"><Size x="7" y="8"/></Frame>')
    Xml.registerVirtual(w, "Direct", node, XmlBuild.session(ctx))
    A.same({ _G.CreateFrame("Frame", nil, nil, "Direct"):GetSize() }, { 7, 8 })
  end)
end

local function test_own_anchors_replace_inherited_ones_assumed() -- (X4)
  local xml = [[
<Ui>
  <Frame name="AnT" virtual="true"><Anchors><Anchor point="TOPLEFT"/></Anchors></Frame>
  <Frame name="An" inherits="AnT"><Anchors><Anchor point="BOTTOMRIGHT"/></Anchors></Frame>
</Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.An:GetNumPoints(), 1)
    A.eq(_G.An:GetPoint(1), "BOTTOMRIGHT")
  end)
end

local function test_later_registration_replaces_the_earlier_assumed() -- (X14)
  H.withXml({}, function(w, ctx)
    local session = XmlBuild.session(ctx)
    Xml.registerVirtual(w, "Dup", XmlParse.parse('<Frame virtual="true"><Size x="1" y="1"/></Frame>'), session)
    Xml.registerVirtual(w, "Dup", XmlParse.parse('<Frame virtual="true"><Size x="2" y="2"/></Frame>'), session)
    A.same({ _G.CreateFrame("Frame", nil, nil, "Dup"):GetSize() }, { 2, 2 })
  end)
end

local function test_xml_template_inherits_a_kit_template_and_unknown_names_still_count()
  local xml = '<Ui><Button name="PbT" virtual="true" inherits="UIPanelButtonTemplate"/></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.CreateFrame("Button", nil, nil, "PbT").Left:GetObjectType(), "Texture")
    _G.CreateFrame("Frame", nil, nil, "NoSuch")
    A.eq(w.unscripted["template:NoSuch"], 1)
  end)
end

local function test_a_kit_template_in_a_list_still_applies_beside_an_xml_one()
  H.withXml({ ["Ui.xml"] = TPL }, function(w, ctx)
    logTo(w)
    H.load(w, ctx, "Ui.xml")
    local f = _G.CreateFrame("Button", nil, nil, "UIPanelButtonTemplate, BoxT")
    A.same({ f.Left:GetObjectType(), f.Title:GetText() }, { "Texture", "T" })
  end)
end

local function test_dollar_parent_of_an_anonymous_target_assumed() -- (X2)
  H.withXml({ ["Ui.xml"] = TPL }, function(w, ctx)
    logTo(w)
    H.load(w, ctx, "Ui.xml")
    local f = _G.CreateFrame("Frame", nil, nil, "BoxT")
    A.eq(_G.Ok, f.Ok)
  end)
end

local function test_virtual_font_string_applies_to_a_region_that_inherits_it()
  local xml = [[
<Ui>
  <FontString name="FsT" virtual="true" text="Hi" justifyH="LEFT"/>
  <Frame name="Hold"><Layers><Layer><FontString parentKey="L" inherits="FsT"/></Layer></Layers></Frame>
</Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.Hold.L:GetText(), _G.Hold.L:GetJustifyH() }, { "Hi", "LEFT" })
    A.eq(_G.FsT, nil)
    A.eq(table.concat(ctx.report, "\n"), "")
  end)
end

-- source: wiki XML/LayoutFrame, hidden "Controls the frame's initial visibility" (row X7)
local function test_hidden_false_shows_what_a_template_hid()
  local xml =
    '<Ui><Frame name="HT" virtual="true" hidden="true"/><Frame name="H1" inherits="HT" hidden="false"/><Frame name="H2" inherits="HT"/></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.H1:IsShown(), _G.H2:IsShown() }, { true, false })
  end)
end

local function test_create_texture_applies_its_xml_template_and_counts_an_unknown_one()
  H.withXml({ ["Ui.xml"] = '<Ui><Texture name="XmlTexVirtual" virtual="true" alpha="0.5"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    A.eq(frame:CreateTexture(nil, "ARTWORK", "XmlTexVirtual"):GetAlpha(), 0.5)
    A.eq(frame:CreateTexture(nil, "ARTWORK", "NoTexTemplate", 2):GetDrawLayer(), "ARTWORK")
    A.eq(w.unscripted["template:NoTexTemplate"], 1)
  end)
end

-- row X25: a template root's parentKey / parentArray lands on the inheriting widget's parent; the element's own wins
local function test_template_root_parent_key_and_array_reach_the_inheriting_widgets_parent()
  local xml = [[
<Ui>
  <Button name="SlotT" parentArray="Slots" virtual="true"/>
  <Frame name="PaneT" parentKey="Pane" virtual="true"/>
  <Texture name="GlowT" parentKey="Glow" virtual="true"/>
  <Frame name="Box"><Frames>
    <Button name="$parentSlot1" inherits="SlotT"/><Button name="$parentSlot2" inherits="SlotT"/>
    <Frame name="$parentPane" inherits="PaneT"/><Frame parentKey="Own" inherits="PaneT"/>
  </Frames><Layers><Layer><Texture name="$parentGlow" inherits="GlowT"/></Layer></Layers></Frame>
</Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local box = _G.Box
    A.same(box.Slots, { _G.BoxSlot1, _G.BoxSlot2 })
    A.same({ box.Pane == _G.BoxPane, box.Own ~= nil, box.Own ~= box.Pane, box.Glow == _G.BoxGlow }, { true, true, true, true })
    local slot = _G.CreateFrame("Button", nil, box, "SlotT") -- CreateFrame's template list: assumed
    A.eq(box.Slots[3], slot)
  end)
end

return function()
  test_template_root_parent_key_and_array_reach_the_inheriting_widgets_parent()
  test_hidden_false_shows_what_a_template_hid()
  test_create_texture_applies_its_xml_template_and_counts_an_unknown_one()
  test_virtual_template_builds_through_createframe()
  test_virtual_element_builds_no_frame_and_no_global()
  test_on_load_runs_once_when_an_xml_element_inherits_a_virtual()
  test_script_error_of_a_virtual_names_the_xml_file_and_line()
  test_nested_virtual_frame_registers_too()
  test_virtual_without_a_name_is_reported_and_skipped()
  test_inherited_template_chain_and_own_size_merge_per_axis_assumed()
  test_inherits_list_applies_in_order_and_the_last_template_wins_assumed()
  test_script_without_inherit_replaces_the_template_one_assumed()
  test_script_inherit_hooks_the_template_script()
  test_script_inherit_prepend_and_append_order_assumed()
  test_register_virtual_directly()
  test_own_anchors_replace_inherited_ones_assumed()
  test_later_registration_replaces_the_earlier_assumed()
  test_xml_template_inherits_a_kit_template_and_unknown_names_still_count()
  test_a_kit_template_in_a_list_still_applies_beside_an_xml_one()
  test_dollar_parent_of_an_anonymous_target_assumed()
  test_virtual_font_string_applies_to_a_region_that_inherits_it()
end
