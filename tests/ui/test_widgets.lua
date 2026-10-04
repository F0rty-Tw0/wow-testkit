-- CreateFrame / CreateFont: method assembly from Ketho WidgetAPI, the generic Set/Get rule, argument checks.
local A = require("assert")
local HW = require("tests.helpers.widgets")
local Widgets = require("ui.widgets")

local withWidgets = HW.withWidgets
-- In Ketho WidgetAPI's retail Frame methods but not vanilla's (checked 2026-10-04).
local RETAIL_ONLY_FRAME_METHOD = "CreateVectorGraphics"
local FONT_PATH = "Fonts\\FRIZQT__.TTF"

local function test_named_frame_sets_global_until_destroy()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame", "MyFrame")
    A.eq(_G.MyFrame, f)
  end)
  A.eq(_G.MyFrame, nil)
end

local function test_frame_keeps_no_fields_of_its_own()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:SetWidth(10)
    A.eq(next(f), nil)
  end)
end

local function test_retail_only_method_is_missing_on_vanilla()
  withWidgets("retail", function()
    A.eq(type(_G.CreateFrame("Frame")[RETAIL_ONLY_FRAME_METHOD]), "function")
  end)
  withWidgets("vanilla", function()
    A.eq(_G.CreateFrame("Frame")[RETAIL_ONLY_FRAME_METHOD], nil)
  end)
end

local function test_generic_getter_returns_setter_args()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:SetID(7)
    A.eq(f:GetID(), 7)
  end)
end

local function test_unset_generic_getter_counts_unscripted()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    A.eq(f:GetID(), 0)
    A.eq(w.unscripted["Frame:GetID"], 1)
  end)
end

local function test_unknown_verb_method_counts_unscripted()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    A.eq(select("#", f:Raise()), 0)
    A.eq(w.unscripted["Frame:Raise"], 1)
  end)
end

local function test_frame_type_is_case_insensitive()
  withWidgets("retail", function()
    A.eq(_G.CreateFrame("button"):GetObjectType(), "Button")
  end)
end

local function test_unknown_frame_type_errors_naming_it()
  withWidgets("retail", function()
    A.errors(function()
      _G.CreateFrame("NotAFrameType")
    end, "NotAFrameType")
    A.errors(function()
      _G.CreateFrame("Texture")
    end, "Texture")
  end)
end

local function test_bad_argument_type_errors_in_addon_context()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    local message = A.errors(function()
      w:run("addon", f.SetWidth, f, {})
    end, "Frame:SetWidth")
    A.contains(message, "retail")
  end)
end

local function test_nil_arguments_are_not_checked()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    w:run("addon", f.SetWidth, f)
  end)
end

local function test_create_frame_passes_template_to_hook()
  withWidgets("retail", function()
    local original = Widgets.applyTemplates
    local got
    Widgets.applyTemplates = function(_, frame, templates)
      got = { frame = frame, templates = templates }
    end
    local ok, err = pcall(_G.CreateFrame, "Frame", nil, nil, "BackdropTemplate")
    Widgets.applyTemplates = original
    assert(ok, err)
    A.eq(got.templates, "BackdropTemplate")
    A.eq(got.frame:GetObjectType(), "Frame")
  end)
end

local function test_named_font_registers_global()
  withWidgets("retail", function()
    _G.CreateFont("MyFont")
    A.eq(_G.MyFont:GetName(), "MyFont")
  end)
end

local function test_font_set_font_round_trips()
  withWidgets("vanilla", function()
    local font = _G.CreateFont("MyFont")
    font:SetFont(FONT_PATH, 14, "OUTLINE")
    A.same({ font:GetFont() }, { FONT_PATH, 14, "OUTLINE" })
  end)
end

return function()
  test_named_frame_sets_global_until_destroy()
  test_frame_keeps_no_fields_of_its_own()
  test_retail_only_method_is_missing_on_vanilla()
  test_generic_getter_returns_setter_args()
  test_unset_generic_getter_counts_unscripted()
  test_unknown_verb_method_counts_unscripted()
  test_frame_type_is_case_insensitive()
  test_unknown_frame_type_errors_naming_it()
  test_bad_argument_type_errors_in_addon_context()
  test_nil_arguments_are_not_checked()
  test_create_frame_passes_template_to_hook()
  test_named_font_registers_global()
  test_font_set_font_round_trips()
end
