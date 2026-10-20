-- CreateFrame / CreateFont: method assembly from Ketho WidgetAPI, the generic Set/Get rule, argument checks.
local A = require("assert")
local HW = require("tests.helpers.widgets")
local Rec = require("tests.helpers.input")
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

local function registerPill(w, seen)
  Widgets.registerIntrinsic(w, "Pill", "Button", {
    init = function(world, obj, st)
      seen.inits = (seen.inits or 0) + 1
      seen.initArgs = { world, obj, st }
    end,
    Poke = function(world, obj, st, ...)
      seen.poke = { world, obj, st, ... }
    end,
  })
end

local function test_intrinsic_type_has_its_methods_and_reports_its_base_type_assumed()
  withWidgets("retail", function(w)
    local seen = {}
    registerPill(w, seen)
    local pill = _G.CreateFrame("pill")
    A.eq(pill:GetObjectType(), "Button") -- D8 (assumed): an intrinsic reports its base type
    A.eq(pill:IsObjectType("Pill"), true)
    A.eq(pill:IsObjectType("Button"), true)
    A.eq(pill:IsObjectType("Frame"), true)
    pill:Poke(1, "x")
    A.eq(seen.poke[1], w)
    A.eq(seen.poke[2], pill)
    A.eq(seen.poke[3], w.ui.state[pill])
    A.same({ seen.poke[4], seen.poke[5] }, { 1, "x" })
  end)
end

local function test_intrinsic_frame_runs_the_base_types_button_methods()
  withWidgets("retail", function(w)
    registerPill(w, {})
    local pill = _G.CreateFrame("Pill")
    local log = Rec.record(pill, { "OnClick" })
    pill:Click()
    A.same(log, { { "OnClick", "LeftButton", false } })
  end)
end

local function test_intrinsic_scripts_follow_the_base_type_assumed()
  withWidgets("retail", function(w)
    registerPill(w, {})
    local pill = _G.CreateFrame("Pill")
    A.eq(w.ui.state[pill].plan.intrinsic, "Pill")
    A.eq(pill:HasScript("OnClick"), true)
    A.eq(pill:HasScript("OnBogus"), false)
    A.errors(function()
      pill:SetScript("OnBogus", function() end)
    end, "Button has no script handler 'OnBogus' on retail")
  end)
end

local function test_intrinsic_init_runs_once_per_frame_and_is_not_a_method()
  withWidgets("retail", function(w)
    local seen = {}
    registerPill(w, seen)
    local first = _G.CreateFrame("Pill")
    A.eq(seen.inits, 1)
    A.eq(seen.initArgs[2], first)
    _G.CreateFrame("Pill")
    A.eq(seen.inits, 2)
    A.eq(first.init, nil)
  end)
end

local function test_intrinsic_is_per_world_and_leaves_the_base_class_alone_assumed()
  withWidgets("retail", function(w)
    registerPill(w, {})
    A.eq(_G.CreateFrame("Button").Poke, nil)
    A.eq(w.ui.create("Pill", nil, nil):GetObjectType(), "Button") -- D8 (assumed)
  end)
  withWidgets("retail", function()
    A.errors(function()
      _G.CreateFrame("Pill")
    end, "unknown frame type 'Pill'")
  end)
end

local function test_register_intrinsic_rejects_an_unknown_base_and_an_existing_type()
  withWidgets("retail", function(w)
    A.errors(function()
      Widgets.registerIntrinsic(w, "Pill", "NoSuchBase", {})
    end, "registerIntrinsic: unknown base type 'NoSuchBase' on retail")
    A.errors(function()
      Widgets.registerIntrinsic(w, "Button", "Frame", {})
    end, "registerIntrinsic: 'Button' is already a widget type on retail")
  end)
end

local function test_intrinsic_scripts_run_before_the_frames_handler_and_survive_set_script()
  withWidgets("retail", function(w)
    local order = {}
    Widgets.registerIntrinsic(w, "Pill", "Button", {
      scripts = {
        OnMouseDown = function(world, obj, st, button)
          order[#order + 1] = { "intrinsic", world, obj, st, button }
        end,
      },
    })
    local pill = _G.CreateFrame("Pill")
    pill:SetScript("OnMouseDown", function(_, button)
      order[#order + 1] = { "addon", button }
    end)
    w:callScript(pill, "OnMouseDown", "LeftButton")
    A.eq(#order, 2)
    A.same({ order[1][1], order[1][5], order[2][1], order[2][2] }, { "intrinsic", "LeftButton", "addon", "LeftButton" })
    A.eq(order[1][2], w)
    A.eq(order[1][3], pill)
    A.eq(order[1][4], w.ui.state[pill])
    A.eq(_G.CreateFrame("Button").OnMouseDown, nil)
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
  test_intrinsic_type_has_its_methods_and_reports_its_base_type_assumed()
  test_intrinsic_frame_runs_the_base_types_button_methods()
  test_intrinsic_scripts_follow_the_base_type_assumed()
  test_intrinsic_init_runs_once_per_frame_and_is_not_a_method()
  test_intrinsic_is_per_world_and_leaves_the_base_class_alone_assumed()
  test_register_intrinsic_rejects_an_unknown_base_and_an_existing_type()
  test_intrinsic_scripts_run_before_the_frames_handler_and_survive_set_script()
end
