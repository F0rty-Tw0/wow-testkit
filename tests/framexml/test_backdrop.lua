-- BackdropTemplateMixin: the backdrop methods a BackdropTemplate frame gets. Rule tags V<n> and W<n> name rows of
-- docs/client-sources.md.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HX = require("tests.helpers.xml")

local withFrameXML = HF.withFrameXML

local INFO = { bgFile = "Interface\\Buttons\\WHITE8X8", tile = true, tileSize = 16 }

local function backdropFrame()
  return _G.CreateFrame("Frame", nil, _G.UIParent, "BackdropTemplate")
end

local function test_template_frames_get_set_backdrop()
  withFrameXML("retail", function()
    A.eq(type(backdropFrame().SetBackdrop), "function")
    A.eq(_G.CreateFrame("Frame").SetBackdrop, nil)
  end)
end

local function test_get_backdrop_returns_the_table_passed_and_nil_clears()
  withFrameXML("retail", function()
    local frame = backdropFrame()
    A.eq(frame:GetBackdrop(), nil)
    frame:SetBackdrop(INFO)
    A.eq(frame:GetBackdrop(), INFO)
    frame:SetBackdrop(nil)
    A.eq(frame:GetBackdrop(), nil)
  end)
end

local function test_colours_of_a_new_backdrop_read_white() -- (V13)
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    A.same({ frame:GetBackdropColor() }, { 1, 1, 1, 1 })
    A.same({ frame:GetBackdropBorderColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_omitted_alpha_is_one() -- (V13)
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:SetBackdropColor(0.1, 0.2, 0.3)
    frame:SetBackdropBorderColor(0.4, 0.5, 0.6)
    A.same({ frame:GetBackdropColor() }, { 0.1, 0.2, 0.3, 1 })
    A.same({ frame:GetBackdropBorderColor() }, { 0.4, 0.5, 0.6, 1 })
  end)
end

local function test_colours_without_a_backdrop_are_ignored_and_read_nothing() -- (V13)
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdropColor(0, 0, 0, 0.5)
    A.eq(select("#", frame:GetBackdropColor()), 0)
    A.eq(select("#", frame:GetBackdropBorderColor()), 0)
    frame:SetBackdrop(INFO)
    A.same({ frame:GetBackdropColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_set_backdrop_resets_the_colours() -- (V13)
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame:SetBackdrop({ bgFile = INFO.bgFile })
    A.same({ frame:GetBackdropColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_mixin_methods_do_not_count_as_unscripted()
  withFrameXML("retail", function(w)
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:SetBackdropColor(0, 0, 0)
    A.eq(w.unscripted["template:BackdropTemplate"], nil)
    A.eq(w.unscripted["Frame:SetBackdrop"], nil)
  end)
end

local function rgbColor(r, g, b)
  return {
    r = r,
    g = g,
    b = b,
    GetRGB = function(self)
      return self.r, self.g, self.b
    end,
  }
end

local function test_set_backdrop_with_the_table_already_set_keeps_the_colours() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame:SetBackdrop(INFO)
    A.same({ frame:GetBackdropColor() }, { 0, 0, 0, 0.5 })
  end)
end

local function test_set_backdrop_sets_the_backdrop_info_field() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    A.eq(frame.backdropInfo, INFO)
    A.eq(frame:HasBackdropInfo(INFO), true)
    A.eq(frame:HasBackdropInfo({}), false)
  end)
end

local function test_set_backdrop_without_a_file_clears() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:SetBackdrop({ edgeSize = 8 })
    A.eq(frame:GetBackdrop(), nil)
    A.eq(frame.backdropInfo, nil)
  end)
end

local function test_on_backdrop_loaded_applies_the_frame_fields() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame.backdropInfo = { bgFile = INFO.bgFile, edgeSize = 8 }
    frame.backdropColor = rgbColor(0, 0, 0)
    frame.backdropColorAlpha = 0.5
    frame.backdropBorderColor = rgbColor(1, 0, 0)
    frame:OnBackdropLoaded()
    A.eq(frame:GetBackdrop().edgeSize, 8)
    A.same({ frame:GetBackdropColor() }, { 0, 0, 0, 0.5 })
    A.same({ frame:GetBackdropBorderColor() }, { 1, 0, 0, 1 })
  end)
end

local function test_on_backdrop_loaded_reads_plain_colour_tables_assumed() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame.backdropInfo = INFO
    frame.backdropColor = { r = 0.2, g = 0.4, b = 0.6 }
    frame:OnBackdropLoaded()
    A.same({ frame:GetBackdropColor() }, { 0.2, 0.4, 0.6, 1 })
  end)
end

local function test_on_backdrop_loaded_leaves_unset_colours_white() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame.backdropInfo = INFO
    frame:OnBackdropLoaded()
    A.same({ frame:GetBackdropColor() }, { 1, 1, 1, 1 })
    A.same({ frame:GetBackdropBorderColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_on_backdrop_loaded_without_info_does_nothing() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:OnBackdropLoaded()
    A.eq(frame:GetBackdrop(), nil)
  end)
end

local function test_on_backdrop_loaded_drops_info_without_a_file() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame.backdropInfo = { edgeSize = 8 }
    frame:OnBackdropLoaded()
    A.same({ frame.backdropInfo, frame:GetBackdrop() }, {})
  end)
end

local function test_on_backdrop_loaded_passes_the_border_blend_mode() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    local seen
    frame.backdropInfo = INFO
    frame.backdropBorderBlendMode = "ADD"
    frame.SetBorderBlendMode = function(_, mode)
      seen = mode
    end
    frame:OnBackdropLoaded()
    A.eq(seen, "ADD")
  end)
end

local function test_apply_backdrop_uses_the_info_field_and_resets_the_colours() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    local other = { bgFile = INFO.bgFile, edgeSize = 4 }
    frame:SetBackdrop(INFO)
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame.backdropColor = rgbColor(1, 0, 0)
    frame.backdropInfo = other
    frame:ApplyBackdrop()
    A.eq(frame:GetBackdrop(), other)
    A.same({ frame:GetBackdropColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_apply_backdrop_without_info_is_an_error() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    A.eq((pcall(frame.ApplyBackdrop, frame)), false)
  end)
end

local function test_clear_backdrop_removes_the_backdrop() -- W47
  withFrameXML("retail", function()
    local frame = backdropFrame()
    frame:SetBackdrop(INFO)
    frame:ClearBackdrop()
    A.same({ frame:GetBackdrop(), frame.backdropInfo }, {})
    A.eq(select("#", frame:GetBackdropColor()), 0)
  end)
end

local XML = [[<Ui><Frame name="XmlBd" inherits="BackdropTemplate"><KeyValues>
  <KeyValue key="backdropInfo" value="XML_BACKDROP_INFO" type="global"/>
  <KeyValue key="backdropColorAlpha" value="0.25" type="number"/>
</KeyValues></Frame></Ui>]]

local function test_backdrop_template_applies_the_key_values_when_the_frame_loads() -- W47
  HX.withXml({ ["a.xml"] = XML }, function(w, ctx)
    rawset(_G, "XML_BACKDROP_INFO", INFO)
    HX.load(w, ctx, "a.xml")
    A.eq(_G.XmlBd:GetBackdrop(), INFO)
    A.same({ _G.XmlBd:GetBackdropColor() }, { 1, 1, 1, 0.25 })
  end)
end

local function test_create_frame_with_the_template_still_has_no_backdrop() -- W47
  withFrameXML("retail", function()
    A.eq(backdropFrame():GetBackdrop(), nil)
  end)
end

return function()
  test_template_frames_get_set_backdrop()
  test_get_backdrop_returns_the_table_passed_and_nil_clears()
  test_colours_of_a_new_backdrop_read_white()
  test_omitted_alpha_is_one()
  test_colours_without_a_backdrop_are_ignored_and_read_nothing()
  test_set_backdrop_resets_the_colours()
  test_mixin_methods_do_not_count_as_unscripted()
  test_set_backdrop_with_the_table_already_set_keeps_the_colours()
  test_set_backdrop_sets_the_backdrop_info_field()
  test_set_backdrop_without_a_file_clears()
  test_on_backdrop_loaded_applies_the_frame_fields()
  test_on_backdrop_loaded_reads_plain_colour_tables_assumed()
  test_on_backdrop_loaded_leaves_unset_colours_white()
  test_on_backdrop_loaded_without_info_does_nothing()
  test_on_backdrop_loaded_drops_info_without_a_file()
  test_on_backdrop_loaded_passes_the_border_blend_mode()
  test_apply_backdrop_uses_the_info_field_and_resets_the_colours()
  test_apply_backdrop_without_info_is_an_error()
  test_clear_backdrop_removes_the_backdrop()
  test_backdrop_template_applies_the_key_values_when_the_frame_loads()
  test_create_frame_with_the_template_still_has_no_backdrop()
end
