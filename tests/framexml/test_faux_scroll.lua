-- FauxScrollFrame_* and ScrollFrameTemplate_OnMouseWheel (framexml/fakes/faux_scroll.lua). Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function newScroll(name)
  return _G.CreateFrame("ScrollFrame", name, _G.UIParent, "FauxScrollFrameTemplate")
end

local function test_update_answers_1_when_the_scroll_bar_shows_and_nil_when_not() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    A.eq(_G.FauxScrollFrame_Update(sf, 100, 10, 16), 1)
    A.eq(sf:IsShown(), true)
    A.eq(_G.FauxScrollFrame_Update(sf, 5, 10, 16), nil)
    A.eq(sf:IsShown(), false)
  end)
end

local function test_update_sizes_the_scroll_bar_and_child_to_the_item_count() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    _G.FauxScrollFrame_Update(sf, 100, 10, 16)
    local min, max = sf.ScrollBar:GetMinMaxValues()
    A.same({ min, max }, { 0, 1440 })
    A.eq(sf.ScrollBar:GetValueStep(), 16)
    A.eq(sf.ScrollChildFrame:GetHeight(), 1600)
  end)
end

local function test_update_keeps_a_range_of_zero_when_everything_fits_and_always_show_is_set() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    A.eq(_G.FauxScrollFrame_Update(sf, 5, 10, 16, nil, nil, nil, nil, nil, nil, true), 1)
    local _, max = sf.ScrollBar:GetMinMaxValues()
    A.eq(max, 0)
  end)
end

local function test_update_resets_the_scroll_bar_when_it_hides() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    _G.FauxScrollFrame_Update(sf, 100, 10, 16)
    sf.ScrollBar:SetValue(160)
    _G.FauxScrollFrame_Update(sf, 5, 10, 16)
    A.eq(sf.ScrollBar:GetValue(), 0)
  end)
end

local function test_update_widens_the_rows_by_whether_the_bar_shows() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    local rows = {}
    for i = 1, 3 do
      rows[i] = _G.CreateFrame("Button", "FauxRow" .. i, _G.UIParent)
    end
    _G.FauxScrollFrame_Update(sf, 100, 3, 16, "FauxRow", 100, 120)
    A.same({ rows[1]:GetWidth(), rows[3]:GetWidth() }, { 100, 100 })
    _G.FauxScrollFrame_Update(sf, 2, 3, 16, "FauxRow", 100, 120)
    A.same({ rows[1]:GetWidth(), rows[3]:GetWidth() }, { 120, 120 })
  end)
end

local function test_update_sets_the_highlight_width_by_whether_the_bar_shows() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    local highlight = _G.CreateFrame("Frame", nil, _G.UIParent)
    _G.FauxScrollFrame_Update(sf, 100, 3, 16, nil, nil, nil, highlight, 80, 95)
    A.eq(highlight:GetWidth(), 80)
    _G.FauxScrollFrame_Update(sf, 2, 3, 16, nil, nil, nil, highlight, 80, 95)
    A.eq(highlight:GetWidth(), 95)
  end)
end

local function test_update_disables_the_arrows_at_the_ends() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    _G.FauxScrollFrame_Update(sf, 100, 10, 16)
    A.eq(sf.ScrollBar.ScrollUpButton:IsEnabled(), false)
    A.eq(sf.ScrollBar.ScrollDownButton:IsEnabled(), true)
    sf.ScrollBar:SetValue(1440)
    _G.FauxScrollFrame_Update(sf, 100, 10, 16)
    A.eq(sf.ScrollBar.ScrollUpButton:IsEnabled(), true)
    A.eq(sf.ScrollBar.ScrollDownButton:IsEnabled(), false)
  end)
end

local function test_offset_round_trips_and_defaults_to_zero() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    A.eq(_G.FauxScrollFrame_GetOffset(sf), 0)
    _G.FauxScrollFrame_SetOffset(sf, 7)
    A.eq(_G.FauxScrollFrame_GetOffset(sf), 7)
  end)
end

local function test_on_vertical_scroll_rounds_the_offset_and_calls_the_update_function() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    _G.FauxScrollFrame_Update(sf, 100, 10, 16)
    local calls = {}
    _G.FauxScrollFrame_OnVerticalScroll(sf, 48, 16, function(frame)
      calls[#calls + 1] = frame
    end)
    A.eq(_G.FauxScrollFrame_GetOffset(sf), 3)
    A.same(calls, { sf })
    A.eq(sf.ScrollBar:GetValue(), 48)
    _G.FauxScrollFrame_OnVerticalScroll(sf, 40, 16)
    A.eq(_G.FauxScrollFrame_GetOffset(sf), 3)
    _G.FauxScrollFrame_OnVerticalScroll(sf, 39, 16)
    A.eq(_G.FauxScrollFrame_GetOffset(sf), 2)
  end)
end

local function test_a_named_frame_finds_its_children_by_key() -- W71
  withFrameXML("retail", function()
    local sf = newScroll("FauxNamed")
    A.eq(_G.FauxScrollFrame_Update(sf, 100, 10, 16), 1)
    A.same({ sf.ScrollBar:GetMinMaxValues() }, { 0, 1440 })
  end)
end

local function test_mouse_wheel_steps_the_scroll_bar_by_half_its_height() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    sf.ScrollBar:SetHeight(40)
    sf.ScrollBar:SetMinMaxValues(0, 100)
    sf.ScrollBar:SetValue(50)
    _G.ScrollFrameTemplate_OnMouseWheel(sf, 1)
    A.eq(sf.ScrollBar:GetValue(), 30)
    _G.ScrollFrameTemplate_OnMouseWheel(sf, -1)
    _G.ScrollFrameTemplate_OnMouseWheel(sf, -1)
    A.eq(sf.ScrollBar:GetValue(), 70)
  end)
end

local function test_mouse_wheel_prefers_the_bars_scroll_step_and_an_explicit_bar() -- W71
  withFrameXML("retail", function()
    local sf = newScroll()
    local other = _G.CreateFrame("Slider", nil, _G.UIParent)
    other:SetMinMaxValues(0, 100)
    other:SetValue(50)
    other.scrollStep = 7
    _G.ScrollFrameTemplate_OnMouseWheel(sf, -1, other)
    A.eq(other:GetValue(), 57)
  end)
end

return function()
  test_update_answers_1_when_the_scroll_bar_shows_and_nil_when_not()
  test_update_sizes_the_scroll_bar_and_child_to_the_item_count()
  test_update_keeps_a_range_of_zero_when_everything_fits_and_always_show_is_set()
  test_update_resets_the_scroll_bar_when_it_hides()
  test_update_widens_the_rows_by_whether_the_bar_shows()
  test_update_sets_the_highlight_width_by_whether_the_bar_shows()
  test_update_disables_the_arrows_at_the_ends()
  test_offset_round_trips_and_defaults_to_zero()
  test_on_vertical_scroll_rounds_the_offset_and_calls_the_update_function()
  test_a_named_frame_finds_its_children_by_key()
  test_mouse_wheel_steps_the_scroll_bar_by_half_its_height()
  test_mouse_wheel_prefers_the_bars_scroll_step_and_an_explicit_bar()
end
