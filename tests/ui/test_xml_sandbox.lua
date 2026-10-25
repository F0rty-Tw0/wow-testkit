-- A global an XML attribute or a widget method resolves by name is answered the way addon code sees it: the host's
-- io, debug, require and _G never reach a frame, an anchor or an addon's hands, while real globals still resolve.
local A = require("assert")
local Framexml = require("tests.helpers.framexml")
local H = require("tests.helpers.xml")
local TemplateApply = require("ui.template_apply")
local Templates = require("ui.templates")

local HOST_ONLY = { "io", "debug", "require", "package" }

local function test_a_key_value_global_does_not_hand_out_host_tables()
  local xml = [[<Ui><Frame name="SbKv"><KeyValues>
<KeyValue key="hio" value="io" type="global"/><KeyValue key="hdebug" value="debug" type="global"/>
<KeyValue key="hg" value="_G" type="global"/><KeyValue key="hui" value="UIParent" type="global"/>
</KeyValues></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.SbKv.hio, _G.SbKv.hdebug }, {})
    A.eq(_G.SbKv.hg == _G, false) -- the view stands in for _G
    A.eq(_G.SbKv.hui, _G.UIParent)
  end)
end

local function test_a_mixin_attribute_does_not_copy_host_tables_onto_the_frame()
  local xml = [[<Ui><Frame name="SbMxIo" mixin="io"/><Frame name="SbMxG" mixin="_G"/><Frame name="SbMxOk" mixin="SbMixin"/>
<Frame name="SbMxSecure" secureMixin="debug"/></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    w:setGlobal("SbMixin", { Hi = "hi" })
    H.load(w, ctx, "Ui.xml")
    A.same({ _G.SbMxIo.open, _G.SbMxIo.popen, _G.SbMxG.require, _G.SbMxG.io, _G.SbMxSecure.getregistry }, {})
    A.eq(_G.SbMxOk.Hi, "hi")
    A.contains(table.concat(ctx.report, "\n"), "mixin 'io' not found")
  end)
end

local function test_a_relative_to_global_does_not_anchor_to_host_tables()
  local xml = [[<Ui><Frame name="SbRel"><Anchors><Anchor point="CENTER" relativeTo="io"/></Anchors></Frame>
<Frame name="SbRelOk"><Anchors><Anchor point="CENTER" relativeTo="UIParent"/></Anchors></Frame></Ui>]]
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(select(2, _G.SbRel:GetPoint(1)), nil)
    A.contains(table.concat(ctx.report, "\n"), "anchor target 'io' not found")
    A.eq(select(2, _G.SbRelOk:GetPoint(1)), _G.UIParent)
  end)
end

local function test_a_parent_attribute_does_not_parent_to_host_tables()
  local xml = '<Ui><Frame name="SbPar" parent="io"/><Frame name="SbParOk" parent="UIParent"/></Ui>'
  H.withXml({ ["Ui.xml"] = xml }, function(w, ctx)
    H.load(w, ctx, "Ui.xml")
    A.eq(_G.SbPar:GetParent(), nil)
    A.contains(table.concat(ctx.report, "\n"), "parent 'io' not found")
    A.eq(_G.SbParOk:GetParent(), _G.UIParent)
  end)
end

local function test_a_template_mixin_name_does_not_copy_host_tables()
  Framexml.withFrameXML("retail", function(w)
    Templates.TEMPLATES.SbHostMixin = { type = "Frame", inherits = {}, children = {}, mixins = { "io", "SbMixin" } }
    w:setGlobal("SbMixin", { Hi = "hi" })
    local ok, err = pcall(function()
      local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
      TemplateApply.applyList(w, frame, "SbHostMixin")
      A.same({ frame.open, frame.popen }, {})
      A.eq(frame.Hi, "hi")
    end)
    Templates.TEMPLATES.SbHostMixin = nil
    assert(ok, err)
  end)
end

local function test_widget_methods_resolving_a_name_do_not_reach_host_tables()
  Framexml.withFrameXML("retail", function()
    local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    for _, name in ipairs(HOST_ONLY) do
      frame:SetParent(name)
      A.eq(frame:GetParent(), nil)
      frame:SetPoint("CENTER", name)
      A.eq(select(2, frame:GetPoint(1)), nil)
    end
    local text = frame:CreateFontString()
    text:SetFontObject("debug")
    A.eq(text:GetFontObject(), nil)
    frame:SetParent("UIParent")
    A.eq(frame:GetParent(), _G.UIParent)
    frame:SetPoint("CENTER", "UIParent")
    A.eq(select(2, frame:GetPoint(1)), _G.UIParent)
    text:SetFontObject("GameFontNormal")
    A.eq(text:GetFontObject(), _G.GameFontNormal)
  end)
end

return function()
  test_a_key_value_global_does_not_hand_out_host_tables()
  test_a_mixin_attribute_does_not_copy_host_tables_onto_the_frame()
  test_a_relative_to_global_does_not_anchor_to_host_tables()
  test_a_parent_attribute_does_not_parent_to_host_tables()
  test_a_template_mixin_name_does_not_copy_host_tables()
  test_widget_methods_resolving_a_name_do_not_reach_host_tables()
end
