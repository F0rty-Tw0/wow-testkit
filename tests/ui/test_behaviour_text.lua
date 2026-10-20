-- Hand-written text, font and status bar semantics.
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets
local FONT_PATH = "Fonts\\FRIZQT__.TTF"

local function newText()
  return _G.CreateFrame("Frame"):CreateFontString()
end

local function test_string_width_ignores_color_codes_at_default_size()
  withWidgets("retail", function()
    local text = newText()
    text:SetText("|cff00ff00abc|r")
    A.eq(text:GetStringWidth(), 18)
    A.eq(text:GetStringHeight(), 12)
  end)
end

local function test_string_metrics_use_set_font_size()
  withWidgets("retail", function()
    local text = newText()
    text:SetFont(FONT_PATH, 20)
    text:SetText("ab")
    A.eq(text:GetStringWidth(), 20)
    A.eq(text:GetStringHeight(), 20)
  end)
end

local function test_string_metrics_follow_font_object()
  withWidgets("vanilla", function()
    local font = _G.CreateFont("MyFont")
    font:SetFont(FONT_PATH, 16)
    local text = newText()
    text:SetFontObject(font)
    text:SetText("abcd")
    A.eq(text:GetFontObject(), font)
    A.eq(text:GetStringWidth(), 32)
  end)
end

local function test_set_text_round_trips()
  withWidgets("retail", function()
    local text = newText()
    A.eq(text:GetText(), nil) -- (F4) wiki: nil if no text is set
    text:SetText("hi")
    A.eq(text:GetText(), "hi")
    text:SetFormattedText("%d items", 3)
    A.eq(text:GetText(), "3 items")
  end)
end

local function test_set_text_nil_reads_back_nil() -- (F4)
  withWidgets("vanilla", function()
    local text = newText()
    text:SetText("hi")
    text:SetText(nil)
    A.eq(text:GetText(), nil)
  end)
end

local function test_text_color_defaults_alpha_to_one()
  withWidgets("retail", function()
    local text = newText()
    text:SetTextColor(0.1, 0.2, 0.3)
    A.same({ text:GetTextColor() }, { 0.1, 0.2, 0.3, 1 })
  end)
end

local function test_copy_font_object_copies_font_and_color()
  withWidgets("retail", function()
    local source = _G.CreateFont("SourceFont")
    source:SetFont(FONT_PATH, 11, "")
    source:SetTextColor(1, 0, 0)
    local copy = _G.CreateFont("CopyFont")
    copy:CopyFontObject(source)
    A.same({ copy:GetFont() }, { FONT_PATH, 11, "" })
    A.same({ copy:GetTextColor() }, { 1, 0, 0, 1 })
  end)
end

local function test_status_bar_color_round_trips()
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    bar:SetStatusBarColor(0, 1, 0)
    A.same({ bar:GetStatusBarColor() }, { 0, 1, 0, 1 })
  end)
end

local function test_status_bar_value_clamps_to_range()
  withWidgets("retail", function()
    local bar = _G.CreateFrame("StatusBar")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(150)
    A.eq(bar:GetValue(), 100)
    bar:SetMinMaxValues(0, 50)
    A.eq(bar:GetValue(), 50)
    A.same({ bar:GetMinMaxValues() }, { 0, 50 })
  end)
end

local function recordValueChanges(widget)
  local calls = {}
  widget:SetScript("OnValueChanged", function(self, value, userInput)
    calls[#calls + 1] = { self = self, value = value, userInput = userInput }
  end)
  return calls
end

local function test_slider_set_value_fires_value_changed_once()
  withWidgets("retail", function()
    local slider = _G.CreateFrame("Slider")
    slider:SetMinMaxValues(0, 10)
    local calls = recordValueChanges(slider)
    slider:SetValue(5)
    slider:SetValue(5)
    A.same(calls, { { self = slider, value = 5, userInput = false } })
  end)
end

local function test_status_bar_set_value_fires_value_changed()
  withWidgets("vanilla", function()
    local bar = _G.CreateFrame("StatusBar")
    local calls = recordValueChanges(bar)
    bar:SetValue(2)
    A.eq(#calls, 1)
    A.eq(calls[1].value, 2)
  end)
end

local function test_narrowed_range_clamps_value_and_fires()
  withWidgets("retail", function()
    local slider = _G.CreateFrame("Slider")
    slider:SetMinMaxValues(0, 10)
    slider:SetValue(5)
    local calls = recordValueChanges(slider)
    slider:SetMinMaxValues(0, 3)
    A.eq(slider:GetValue(), 3)
    A.same(calls, { { self = slider, value = 3, userInput = false } })
  end)
end

return function()
  test_slider_set_value_fires_value_changed_once()
  test_status_bar_set_value_fires_value_changed()
  test_narrowed_range_clamps_value_and_fires()
  test_string_width_ignores_color_codes_at_default_size()
  test_string_metrics_use_set_font_size()
  test_string_metrics_follow_font_object()
  test_set_text_round_trips()
  test_set_text_nil_reads_back_nil()
  test_text_color_defaults_alpha_to_one()
  test_copy_font_object_copies_font_and_color()
  test_status_bar_color_round_trips()
  test_status_bar_value_clamps_to_range()
end
