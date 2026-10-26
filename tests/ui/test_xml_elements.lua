-- XML frame and region elements: identity attributes, frame and region attributes, mixins, templates, unknown tags.
local A = require("assert")
local H = require("tests.helpers.xml")
local XmlBuild = require("ui.xml_build")
local XmlParse = require("ui.xml_parse")

local BOX = [[
<Ui>
  <Frame name="Box" frameStrata="HIGH" frameLevel="7" alpha="0.5" scale="2" id="9" hidden="true"
         enableMouse="true" movable="true" toplevel="true">
    <Frames>
      <Button name="$parentOk" parentKey="Ok"/>
      <Frame parentArray="rows"/><Frame parentArray="rows"/>
    </Frames>
  </Frame>
</Ui>]]

local function reportText(ctx)
  return table.concat(ctx.report, "\n")
end

local function count(text, needle)
  local n = 0
  for _ in text:gmatch(needle) do
    n = n + 1
  end
  return n
end

-- Builds the region that `xml` describes under `frame`, the way a <Layers> entry will once layers load.
local function region(w, ctx, frame, xml, layer, sub)
  return XmlBuild.region(w, XmlParse.parse(xml), frame, XmlBuild.session(ctx), layer, sub)
end

local function test_frame_attributes_and_nested_frames()
  H.withXml({ ["Ui.xml"] = BOX }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local box = _G.Box
    A.same({ box:GetFrameStrata(), box:GetFrameLevel(), box:GetAlpha(), box:GetScale(), box:GetID() }, { "HIGH", 7, 0.5, 2, 9 })
    A.same({ box:IsShown(), box:IsMouseEnabled(), box:IsMovable(), box:IsToplevel() }, { false, true, true, true })
    A.eq(_G.BoxOk, box.Ok)
    A.same({ box.Ok:GetObjectType(), box.Ok:GetParent() == box }, { "Button", true })
  end)
end

local function test_top_level_frame_without_parent_is_parentless_assumed()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="Lone"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Lone:GetParent(), nil)
  end)
end

local function test_parent_attribute_names_the_global_parent()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="Kid" parent="UIParent"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Kid:GetParent(), _G.UIParent)
  end)
end

local function test_parent_array_collects_children_in_document_order_assumed()
  local xml = '<Ui><Frame name="P"><Frames><Frame parentArray="rows" id="1"/><Frame parentArray="rows" id="2"/></Frames></Frame></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    local rows = _G.P.rows
    A.same({ #rows, rows[1]:GetID(), rows[2]:GetID(), rows[1]:GetParent() == _G.P }, { 2, 1, 2, true })
  end)
end

local function test_unknown_frame_type_is_reported_and_skipped_assumed()
  H.withXml({ ["Ui.xml"] = '<Ui><Frobnicator name="Nope"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "unsupported XML <Frobnicator> ignored")
    A.eq(_G.Nope, nil)
  end)
end

local function test_region_tag_at_top_level_builds_no_frame_assumed()
  H.withXml({ ["Ui.xml"] = '<Ui><Texture name="Tx"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "unsupported XML <Texture> ignored")
    A.eq(_G.Tx, nil)
  end)
end

local function test_unknown_child_element_is_reported_once_per_file_assumed()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="A"><Bogus/></Frame><Frame name="B"><Bogus/></Frame></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(count(reportText(ctx), "unsupported XML <Bogus> ignored"), 1)
    A.eq(_G.B ~= nil, true)
  end)
end

local function test_unsupported_attribute_is_reported_once_per_file()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="Ua" bogus="1"/><Frame name="Ub" bogus="2"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(count(reportText(ctx), "unsupported XML attribute 'bogus' ignored"), 1)
    A.eq(_G.Ub ~= nil, true)
  end)
end

local function test_tag_matches_the_frame_type_ignoring_case_assumed()
  H.withXml({ ["Ui.xml"] = '<Ui><checkbutton name="Cb"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Cb:GetObjectType(), "CheckButton")
  end)
end

local function test_mixin_copies_the_global_table_and_records_its_name()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="Mx" mixin="BoxMixin, OtherMixin"/></Ui>' }, function(w, ctx)
    local hello = function() end
    w:setGlobal("BoxMixin", { Hello = hello })
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Mx.Hello, hello)
    A.same(w.ui.state[_G.Mx].mixins, { "BoxMixin", "OtherMixin" })
  end)
end

local function test_inherits_applies_before_the_elements_own_mixin_assumed()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="Ord" mixin="BoxMixin" inherits="BackdropTemplate"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same(w.ui.state[_G.Ord].mixins, { "BackdropTemplateMixin", "BoxMixin" })
  end)
end

local function test_missing_mixin_is_reported_assumed()
  H.withXml({ ["Ui.xml"] = '<Ui><Frame name="Mx" mixin="BoxMixin, OtherMixin"/></Ui>' }, function(w, ctx)
    w:setGlobal("BoxMixin", {})
    H.load(w, ctx, "Ui.xml")
    A.contains(reportText(ctx), "mixin 'OtherMixin' not found")
    A.eq(_G.Mx ~= nil, true)
  end)
end

local function test_template_inherits_apply_kit_templates()
  H.withXml({ ["Ui.xml"] = '<Ui><Button name="Pb" inherits="UIPanelButtonTemplate"/></Ui>' }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.Pb.Left:GetObjectType(), "Texture")
  end)
end

local function test_texture_region_attributes()
  H.withXml({}, function(w, ctx)
    local frame = _G.CreateFrame("Frame", "Host")
    local tex = region(w, ctx, frame, '<Texture name="T" parentKey="Icon" file="Interface\\X" hidden="true" alpha="0.4"/>', "OVERLAY", 3)
    A.same({ frame.Icon == tex, _G.T == tex, tex:GetObjectType(), tex:GetParent() == frame }, { true, true, "Texture", true })
    A.same({ tex:GetDrawLayer() }, { "OVERLAY", 3 })
    A.same({ tex:GetTexture(), tex:GetAlpha(), tex:IsShown() }, { "Interface\\X", 0.4, false })
  end)
end

local function test_region_defaults_to_artwork_sublevel_zero()
  H.withXml({}, function(w, ctx)
    local tex = region(w, ctx, _G.CreateFrame("Frame"), "<Texture/>")
    A.same({ tex:GetDrawLayer() }, { "ARTWORK", 0 })
  end)
end

local function test_region_name_substitutes_parent_with_its_frame_name_assumed()
  H.withXml({}, function(w, ctx)
    region(w, ctx, _G.CreateFrame("Frame", "Host"), '<Texture name="$parentBg"/>')
    A.eq(_G.HostBg:GetObjectType(), "Texture")
  end)
end

local function test_atlas_region()
  H.withXml({}, function(w, ctx)
    local tex = region(w, ctx, _G.CreateFrame("Frame"), '<Texture atlas="spark" useAtlasSize="true"/>')
    A.eq(tex:GetAtlas(), "spark")
  end)
end

local function test_alpha_mode_sets_the_blend_mode_assumed()
  H.withXml({}, function(w, ctx)
    local tex = region(w, ctx, _G.CreateFrame("Frame"), '<Texture alphaMode="ADD"/>')
    A.eq(tex:GetBlendMode(), "ADD")
  end)
end

local function test_font_string_text_justify_and_font_object_assumed()
  H.withXml({}, function(w, ctx)
    local fs = region(w, ctx, _G.CreateFrame("Frame"), '<FontString text="Hi" justifyH="LEFT" justifyV="TOP" inherits="GameFontNormal"/>')
    A.same({ fs:GetText(), fs:GetJustifyH(), fs:GetJustifyV(), fs:GetFontObject() == _G.GameFontNormal }, { "Hi", "LEFT", "TOP", true })
  end)
end

local function test_font_string_text_names_a_global_string_assumed()
  H.withXml({}, function(w, ctx)
    w:setGlobal("MY_LABEL", "Localized")
    local fs = region(w, ctx, _G.CreateFrame("Frame"), '<FontString text="MY_LABEL"/>')
    A.eq(fs:GetText(), "Localized")
  end)
end

local function test_unsupported_region_attribute_is_reported()
  H.withXml({}, function(w, ctx)
    region(w, ctx, _G.CreateFrame("Frame"), '<Texture bogus="1"/>')
    A.contains(reportText(ctx), "unsupported XML attribute 'bogus' ignored")
  end)
end

local function test_non_region_tag_gives_no_region()
  H.withXml({}, function(w, ctx)
    A.eq(region(w, ctx, _G.CreateFrame("Frame"), "<Frobnicator/>"), nil)
    A.contains(reportText(ctx), "unsupported XML <Frobnicator> ignored")
  end)
end

return function()
  test_frame_attributes_and_nested_frames()
  test_top_level_frame_without_parent_is_parentless_assumed()
  test_parent_attribute_names_the_global_parent()
  test_parent_array_collects_children_in_document_order_assumed()
  test_unknown_frame_type_is_reported_and_skipped_assumed()
  test_region_tag_at_top_level_builds_no_frame_assumed()
  test_unknown_child_element_is_reported_once_per_file_assumed()
  test_unsupported_attribute_is_reported_once_per_file()
  test_tag_matches_the_frame_type_ignoring_case_assumed()
  test_mixin_copies_the_global_table_and_records_its_name()
  test_inherits_applies_before_the_elements_own_mixin_assumed()
  test_missing_mixin_is_reported_assumed()
  test_template_inherits_apply_kit_templates()
  test_texture_region_attributes()
  test_region_defaults_to_artwork_sublevel_zero()
  test_region_name_substitutes_parent_with_its_frame_name_assumed()
  test_atlas_region()
  test_alpha_mode_sets_the_blend_mode_assumed()
  test_font_string_text_justify_and_font_object_assumed()
  test_font_string_text_names_a_global_string_assumed()
  test_unsupported_region_attribute_is_reported()
  test_non_region_tag_gives_no_region()
end
