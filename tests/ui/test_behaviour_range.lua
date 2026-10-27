-- Slider and StatusBar behaviour (ui/behaviour_range.lua): orientation, value steps, fill options and the thumb and bar
-- textures. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets

local function sliderOptions(slider)
  return { slider:GetOrientation(), slider:GetValueStep(), slider:GetStepsPerPage(), slider:GetObeyStepOnDrag() }
end

local function barOptions(bar)
  return { bar:GetReverseFill(), bar:GetFillStyle(), bar:GetRotatesTexture(), bar:GetOrientation() }
end

local function stepSlider(min, step, obey)
  local slider = _G.CreateFrame("Slider")
  slider:SetMinMaxValues(min, 100)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(obey)

  return slider
end

local function test_fresh_slider_defaults() -- V12, W42
  withWidgets("retail", function()
    A.same(sliderOptions(_G.CreateFrame("Slider")), { "VERTICAL", 0, 0, false })
  end)
end

local function test_slider_options_round_trip() -- W42
  withWidgets("retail", function()
    local slider = _G.CreateFrame("Slider")
    slider:SetOrientation("HORIZONTAL")
    slider:SetValueStep(5)
    slider:SetStepsPerPage(3)
    slider:SetObeyStepOnDrag(true)
    A.same(sliderOptions(slider), { "HORIZONTAL", 5, 3, true })
  end)
end

local function test_set_value_snaps_to_the_step_when_obeying_assumed() -- W42
  withWidgets("retail", function()
    local slider = stepSlider(0, 10, true)
    slider:SetValue(34)
    A.eq(slider:GetValue(), 30)
    slider:SetValue(36)
    A.eq(slider:GetValue(), 40)
  end)
end

local function test_snap_counts_from_the_minimum_assumed() -- W42
  withWidgets("retail", function()
    local slider = stepSlider(3, 10, true)
    slider:SetValue(20)
    A.eq(slider:GetValue(), 23)
  end)
end

local function test_a_zero_step_does_not_snap_assumed() -- W42
  withWidgets("retail", function()
    local slider = stepSlider(0, 0, true)
    slider:SetValue(34)
    A.eq(slider:GetValue(), 34)
  end)
end

local function test_a_slider_not_obeying_the_step_does_not_snap_assumed() -- W42
  withWidgets("retail", function()
    local slider = stepSlider(0, 10, false)
    slider:SetValue(36)
    A.eq(slider:GetValue(), 36)
  end)
end

local function test_snapped_value_fires_value_changed_with_the_snapped_value_assumed() -- W42
  withWidgets("retail", function()
    local slider = stepSlider(0, 10, true)
    local seen = {}
    slider:SetScript("OnValueChanged", function(_, value)
      seen[#seen + 1] = value
    end)
    slider:SetValue(34)
    A.same(seen, { 30 })
  end)
end

local function test_a_status_bar_value_never_snaps()
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(34)
    A.eq(bar:GetValue(), 34)
  end)
end

local function test_status_bar_fill_options_round_trip() -- W44
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    A.same(barOptions(bar), { false, "STANDARD", false, "HORIZONTAL" })
    bar:SetReverseFill(true)
    bar:SetFillStyle("CENTER")
    bar:SetRotatesTexture(true)
    bar:SetOrientation("VERTICAL")
    A.same(barOptions(bar), { true, "CENTER", true, "VERTICAL" })
  end)
end

local function test_status_bar_fill_style_enum_values() -- W44
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    for _, style in ipairs({ "STANDARD", "STANDARDNORANGEFILL", "CENTER", "REVERSE" }) do
      bar:SetFillStyle(style)
      A.eq(bar:GetFillStyle(), style)
    end
  end)
end

local function test_status_bar_fill_style_accepts_the_enum_number() -- W44
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    bar:SetFillStyle(2)
    A.eq(bar:GetFillStyle(), "CENTER")
  end)
end

local function test_status_bar_texture_round_trips_through_a_path() -- W44
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    A.eq(bar:GetStatusBarTexture(), nil)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    A.eq(bar:GetStatusBarTexture():GetTexture(), "Interface\\TargetingFrame\\UI-StatusBar")
  end)
end

local function test_status_bar_texture_adopts_a_texture_object() -- W44
  withWidgets("retail", function(w)
    local bar = _G.CreateFrame("StatusBar")
    local tex = bar:CreateTexture()
    bar:SetStatusBarTexture(tex)
    A.eq(bar:GetStatusBarTexture(), tex)
    A.eq(w.ui.state[tex].widgetPart, "bar")
  end)
end

local function test_a_path_after_a_path_reuses_the_bar_texture() -- W44
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    bar:SetStatusBarTexture("a")
    local first = bar:GetStatusBarTexture()
    bar:SetStatusBarTexture("b")
    A.same({ bar:GetStatusBarTexture() == first, first:GetTexture() }, { true, "b" })
  end)
end

local function test_a_path_retextures_an_adopted_bar_texture_assumed() -- W44
  withWidgets("retail", function(w)
    local bar = _G.CreateFrame("StatusBar")
    local own = bar:CreateTexture()
    bar:SetStatusBarTexture(own)
    bar:SetStatusBarTexture("Interface\\Bar")
    A.same({ bar:GetStatusBarTexture() == own, own:GetTexture(), select("#", bar:GetRegions()) }, { true, "Interface\\Bar", 1 })
    A.same({ w.ui.state[own].widgetPart, w.ui.state[own].partOwned }, { "bar", nil })
  end)
end

local function test_a_path_retextures_an_adopted_thumb_assumed() -- W43
  withWidgets("retail", function()
    local slider = _G.CreateFrame("Slider")
    local own = slider:CreateTexture()
    slider:SetThumbTexture(own)
    slider:SetThumbTexture("thumb.blp")
    A.same({ slider:GetThumbTexture() == own, own:GetTexture(), select("#", slider:GetRegions()) }, { true, "thumb.blp", 1 })
  end)
end

-- source: assumed (W43) a thumb another slider adopted no longer fills this slider's thumb.
local function test_a_path_after_another_slider_took_the_thumb_makes_a_new_one_assumed() -- W43
  withWidgets("retail", function(w)
    local a, b = _G.CreateFrame("Slider"), _G.CreateFrame("Slider")
    local shared = a:CreateTexture()
    a:SetThumbTexture(shared)
    b:SetThumbTexture(shared)
    a:SetThumbTexture("thumb.blp")
    local mine = a:GetThumbTexture()
    A.same({ mine ~= shared, mine:GetParent() == a, mine:GetTexture() }, { true, true, "thumb.blp" })
    A.same({ shared:GetTexture(), w.ui.state[shared].widgetPart, b:GetThumbTexture() == shared }, { nil, "thumb", true })
  end)
end

local function test_replacing_the_bar_texture_releases_the_old_one() -- W44
  withWidgets("retail", function(w)
    local bar = _G.CreateFrame("StatusBar")
    local old = bar:CreateTexture()
    local new = bar:CreateTexture()
    bar:SetStatusBarTexture(old)
    bar:SetStatusBarTexture(new)
    A.eq(w.ui.state[old].widgetPart, nil)
    A.eq(w.ui.state[new].widgetPart, "bar")
  end)
end

local function test_replacing_a_made_bar_texture_hides_it() -- W44
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    bar:SetStatusBarTexture("a")
    local made = bar:GetStatusBarTexture()
    bar:SetStatusBarTexture(bar:CreateTexture())
    A.eq(made:IsShown(), false)
  end)
end

local function test_adopting_a_texture_re_parents_it() -- W43
  withWidgets("retail", function()
    local slider = _G.CreateFrame("Slider")
    local thumb = _G.CreateFrame("Frame"):CreateTexture()
    slider:SetThumbTexture(thumb)
    A.eq(thumb:GetParent(), slider)
  end)
end

local function test_setting_the_made_thumb_again_keeps_it_shown() -- W43
  withWidgets("retail", function()
    local slider = _G.CreateFrame("Slider")
    slider:SetThumbTexture("thumb.blp")
    local thumb = slider:GetThumbTexture()
    slider:SetThumbTexture(thumb)
    A.eq(thumb:IsShown(), true)
  end)
end

local function test_thumb_texture_is_a_thumb_part() -- W43
  withWidgets("retail", function(w)
    local slider = _G.CreateFrame("Slider")
    A.eq(slider:GetThumbTexture(), nil)
    local thumb = slider:CreateTexture()
    slider:SetThumbTexture(thumb)
    A.eq(slider:GetThumbTexture(), thumb)
    A.eq(w.ui.state[thumb].widgetPart, "thumb")
  end)
end

local function test_thumb_texture_from_a_path_makes_a_region() -- W43
  withWidgets("retail", function(w)
    local slider = _G.CreateFrame("Slider")
    slider:SetThumbTexture("thumb.blp")
    local thumb = slider:GetThumbTexture()
    A.eq(thumb:GetTexture(), "thumb.blp")
    A.eq(thumb:GetParent(), slider)
    A.eq(w.ui.state[thumb].widgetPart, "thumb")
  end)
end

return function()
  test_fresh_slider_defaults()
  test_slider_options_round_trip()
  test_set_value_snaps_to_the_step_when_obeying_assumed()
  test_snap_counts_from_the_minimum_assumed()
  test_a_zero_step_does_not_snap_assumed()
  test_a_slider_not_obeying_the_step_does_not_snap_assumed()
  test_snapped_value_fires_value_changed_with_the_snapped_value_assumed()
  test_a_status_bar_value_never_snaps()
  test_status_bar_fill_options_round_trip()
  test_status_bar_fill_style_enum_values()
  test_status_bar_fill_style_accepts_the_enum_number()
  test_status_bar_texture_round_trips_through_a_path()
  test_status_bar_texture_adopts_a_texture_object()
  test_a_path_after_a_path_reuses_the_bar_texture()
  test_a_path_retextures_an_adopted_bar_texture_assumed()
  test_a_path_retextures_an_adopted_thumb_assumed()
  test_a_path_after_another_slider_took_the_thumb_makes_a_new_one_assumed()
  test_replacing_the_bar_texture_releases_the_old_one()
  test_replacing_a_made_bar_texture_hides_it()
  test_adopting_a_texture_re_parents_it()
  test_setting_the_made_thumb_again_keeps_it_shown()
  test_thumb_texture_is_a_thumb_part()
  test_thumb_texture_from_a_path_makes_a_region()
end
