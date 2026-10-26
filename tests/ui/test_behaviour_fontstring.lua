-- FontString and font object behaviour (ui/behaviour_fontstring.lua): the text getters and their font object
-- inheritance, max lines and spacing in the height, truncation and the three string widths. Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local A = require("assert")
local HL = require("tests.helpers.layout")
local HW = require("tests.helpers.widgets")
local Layout = require("ui.layout")

local FONT = "Fonts\\FRIZQT__.TTF"
local SCREEN = { width = 1920, height = 1080 }

local function near(actual, expected)
  A.truthy(math.abs(actual - expected) < 1e-9, string.format("expected %s, got %s", expected, actual))
end

local function newText()
  return _G.CreateFrame("Frame"):CreateFontString()
end

-- A font string of size 10 holding text, anchored to the top left of a frame at the screen corner so that Layout.rect
-- resolves it.
local function sizedText(text)
  local root = _G.CreateFrame("Frame")
  root:SetSize(200, 100)
  root:SetPoint("BOTTOMLEFT")
  local fs = root:CreateFontString()
  fs:SetFont(FONT, 10, "")
  fs:SetText(text)
  fs:SetPoint("TOPLEFT")
  return fs
end

local function test_max_lines_and_spacing_change_the_height_assumed() -- W28
  HL.withLayout(SCREEN, function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    fs:SetText("a\nb\nc")
    near(fs:GetHeight(), 34.5)
    fs:SetMaxLines(2)
    near(fs:GetHeight(), 23)
    fs:SetSpacing(2)
    near(fs:GetHeight(), 25)
  end)
end

local function test_layout_rect_follows_max_lines_and_spacing_assumed() -- W28
  HL.withLayout(SCREEN, function(w)
    local fs = sizedText("a\nb\nc")
    near(Layout.rect(w, fs).height, 34.5)
    fs:SetSpacing(2)
    near(Layout.rect(w, fs).height, 38.5)
    fs:SetMaxLines(2)
    near(Layout.rect(w, fs).height, 25)
    fs:SetSpacing(0)
    near(Layout.rect(w, fs).height, 23)
  end)
end

local function test_max_lines_count_wrapped_lines_assumed() -- W28
  HL.withLayout(SCREEN, function(w)
    local fs = sizedText("aaaa bbbb cccc")
    fs:SetWidth(30)
    near(Layout.rect(w, fs).height, 34.5)
    fs:SetMaxLines(2)
    near(Layout.rect(w, fs).height, 23)
  end)
end

local function test_set_text_height_resizes_the_text_assumed() -- W27
  HL.withLayout(SCREEN, function(w)
    local fs = sizedText("ab")
    near(Layout.rect(w, fs).height, 11.5)
    fs:SetTextHeight(20)
    near(Layout.rect(w, fs).height, 23)
    near(Layout.rect(w, fs).width, 20)
  end)
end

local function test_getter_defaults() -- W25
  HW.withWidgets("retail", function()
    local fs = newText()
    A.eq(fs:GetJustifyH(), "CENTER")
    A.eq(fs:GetJustifyV(), "MIDDLE")
    A.eq(fs:GetSpacing(), 0)
    A.eq(fs:GetMaxLines(), 0)
    A.eq(fs:CanWordWrap(), true)
  end)
end

local function test_shadow_defaults_assumed() -- W29
  HW.withWidgets("retail", function()
    local fs = newText()
    A.same({ fs:GetShadowColor() }, { 0, 0, 0, 0 })
    A.same({ fs:GetShadowOffset() }, { 0, 0 })
  end)
end

local function test_setters_round_trip()
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(3)
    fs:SetShadowColor(0.1, 0.2, 0.3, 0.4)
    fs:SetShadowOffset(1, -1)
    fs:SetMaxLines(4)
    fs:SetWordWrap(false)
    A.eq(fs:GetJustifyH(), "LEFT")
    A.eq(fs:GetJustifyV(), "TOP")
    A.eq(fs:GetSpacing(), 3)
    A.same({ fs:GetShadowColor() }, { 0.1, 0.2, 0.3, 0.4 })
    A.same({ fs:GetShadowOffset() }, { 1, -1 })
    A.eq(fs:GetMaxLines(), 4)
    A.eq(fs:CanWordWrap(), false)
  end)
end

local function test_shadow_alpha_defaults_to_one_assumed() -- W29
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetShadowColor(0.1, 0.2, 0.3)
    A.same({ fs:GetShadowColor() }, { 0.1, 0.2, 0.3, 1 })
  end)
end

local function test_font_object_answers_the_getters() -- W25, W29
  HW.withWidgets("retail", function()
    local font = _G.CreateFont("T64Plain")
    A.eq(font:GetJustifyH(), "CENTER")
    A.eq(font:GetJustifyV(), "MIDDLE")
    A.eq(font:GetSpacing(), 0)
    A.same({ font:GetShadowOffset() }, { 0, 0 })
    font:SetJustifyV("BOTTOM")
    A.eq(font:GetJustifyV(), "BOTTOM")
  end)
end

local function test_text_settings_inherit_from_the_font_object_assumed() -- W31
  HW.withWidgets("retail", function()
    local font = _G.CreateFont("T64Source")
    font:SetJustifyH("LEFT")
    font:SetJustifyV("TOP")
    font:SetSpacing(4)
    font:SetShadowColor(1, 0, 0, 1)
    font:SetShadowOffset(2, -2)
    local fs = newText()
    fs:SetFontObject(font)
    A.eq(fs:GetJustifyH(), "LEFT")
    A.eq(fs:GetJustifyV(), "TOP")
    A.eq(fs:GetSpacing(), 4)
    A.same({ fs:GetShadowColor() }, { 1, 0, 0, 1 })
    A.same({ fs:GetShadowOffset() }, { 2, -2 })
    fs:SetJustifyH("RIGHT")
    A.eq(fs:GetJustifyH(), "RIGHT")
    A.eq(fs:GetJustifyV(), "TOP")
  end)
end

local function test_inheritance_follows_a_chain_of_font_objects_assumed() -- W31
  HW.withWidgets("retail", function()
    local base = _G.CreateFont("T64Base")
    base:SetJustifyH("RIGHT")
    local derived = _G.CreateFont("T64Derived")
    derived:SetFontObject(base)
    local fs = newText()
    fs:SetFontObject(derived)
    A.eq(fs:GetJustifyH(), "RIGHT")
    derived:SetJustifyH("LEFT")
    A.eq(fs:GetJustifyH(), "LEFT")
  end)
end

local function test_edit_box_justify_inherits_from_the_font_object_assumed() -- W31
  HW.withWidgets("retail", function()
    local font = _G.CreateFont("T64Edit")
    font:SetJustifyH("RIGHT")
    local box = _G.CreateFrame("EditBox")
    A.eq(box:GetJustifyH(), "CENTER")
    box:SetFontObject(font)
    A.eq(box:GetJustifyH(), "RIGHT")
    box:SetJustifyH("LEFT")
    A.eq(box:GetJustifyH(), "LEFT")
  end)
end

local function test_copy_font_object_copies_inherited_settings_assumed() -- W31
  HW.withWidgets("retail", function()
    local base = _G.CreateFont("T64CopyBase")
    base:SetJustifyH("RIGHT")
    base:SetSpacing(5)
    local source = _G.CreateFont("T64CopySource")
    source:SetFontObject(base)
    local copy = _G.CreateFont("T64CopyTarget")
    copy:CopyFontObject(source)
    A.eq(copy:GetFontObject(), nil)
    A.eq(copy:GetJustifyH(), "RIGHT")
    A.eq(copy:GetSpacing(), 5)
  end)
end

local function test_set_text_height_changes_size_only_assumed() -- W27
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 12, "OUTLINE")
    fs:SetTextHeight(20)
    A.same({ fs:GetFont() }, { FONT, 20, "OUTLINE" })
  end)
end

local function test_set_text_height_keeps_an_inherited_file_assumed() -- W27
  HW.withWidgets("retail", function()
    local font = _G.CreateFont("T64Height")
    font:SetFont(FONT, 12, "THICKOUTLINE")
    local fs = newText()
    fs:SetFontObject(font)
    fs:SetTextHeight(18)
    A.same({ fs:GetFont() }, { FONT, 18, "THICKOUTLINE" })
    A.same({ font:GetFont() }, { FONT, 12, "THICKOUTLINE" })
  end)
end

local function test_line_height_is_one_line_of_the_current_size_assumed() -- W25, Measure
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    near(fs:GetLineHeight(), 11.5)
    fs:SetTextHeight(20)
    near(fs:GetLineHeight(), 23)
  end)
end

local function test_unbounded_width_ignores_wrap_assumed() -- W30
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    fs:SetWidth(30)
    fs:SetText("aaaa bbbb")
    A.eq(fs:GetStringWidth(), 45)
    A.eq(fs:GetUnboundedStringWidth(), 45)
  end)
end

local function test_string_width_includes_truncation_unbounded_does_not_assumed() -- W30
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    fs:SetText("aa\nbbbbbb")
    fs:SetMaxLines(1)
    A.eq(fs:GetStringWidth(), 10)
    A.eq(fs:GetUnboundedStringWidth(), 30)
  end)
end

local function test_wrapped_width_includes_wrap_and_truncation_assumed() -- W30
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    fs:SetWidth(30)
    fs:SetText("bbbb aaaaaa")
    A.eq(fs:GetStringWidth(), 55)
    A.eq(fs:GetWrappedWidth(), 30)
    fs:SetMaxLines(1)
    A.eq(fs:GetWrappedWidth(), 20)
    A.eq(fs:GetUnboundedStringWidth(), 55)
  end)
end

local function test_is_truncated_after_max_lines_assumed() -- W26
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    fs:SetWidth(30)
    fs:SetText("aaaa bbbb cccc")
    A.eq(fs:IsTruncated(), false)
    fs:SetMaxLines(1)
    A.eq(fs:IsTruncated(), true)
    fs:SetMaxLines(3)
    A.eq(fs:IsTruncated(), false)
    fs:SetMaxLines(0)
    A.eq(fs:IsTruncated(), false)
  end)
end

local function test_is_truncated_when_a_line_overflows_the_width_assumed() -- W26
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    fs:SetWidth(30)
    fs:SetText("aaaa bbbb")
    fs:SetWordWrap(false)
    A.eq(fs:IsTruncated(), true)
    fs:SetWidth(100)
    A.eq(fs:IsTruncated(), false)
  end)
end

local function test_is_truncated_for_one_word_wider_than_the_width_assumed() -- W26
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    fs:SetWidth(30)
    fs:SetText("aaaaaaaa")
    A.eq(fs:IsTruncated(), true)
  end)
end

local function test_is_truncated_in_a_width_two_anchors_fix_assumed() -- W26
  HL.withLayout(SCREEN, function()
    local root = _G.CreateFrame("Frame")
    root:SetSize(30, 100)
    root:SetPoint("BOTTOMLEFT")
    local fs = root:CreateFontString()
    fs:SetFont(FONT, 10, "")
    fs:SetText("aaaa bbbb")
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT")
    fs:SetPoint("TOPRIGHT")
    A.eq(fs:IsTruncated(), true)
    root:SetWidth(100)
    A.eq(fs:IsTruncated(), false)
  end)
end

local function test_text_without_a_fixed_width_is_not_truncated_assumed() -- W26
  HW.withWidgets("retail", function()
    local fs = newText()
    fs:SetFont(FONT, 10, "")
    fs:SetText("aaaa bbbb")
    fs:SetWordWrap(false)
    A.eq(fs:IsTruncated(), false)
  end)
end

local function test_a_replaced_button_text_stops_following_the_state_font_object_assumed() -- W22
  HW.withWidgets("retail", function()
    local off = _G.CreateFont("T64OffReplaced")
    off:SetFont(FONT, 14, "")
    local button = _G.CreateFrame("Button")
    button:SetDisabledFontObject(off)
    button:SetText("x")
    local old = button:GetFontString()
    local new = button:CreateFontString()
    button:SetFontString(new)
    button:Disable()
    A.eq(old:GetFont(), nil)
    A.same({ new:GetFont() }, { FONT, 14, "" })
  end)
end

local function test_button_text_follows_the_state_font_object_assumed() -- W22
  HW.withWidgets("retail", function()
    local off = _G.CreateFont("T64Off")
    off:SetFont(FONT, 14, "")
    off:SetTextColor(0.5, 0.5, 0.5)
    local button = _G.CreateFrame("Button")
    button:SetDisabledFontObject(off)
    button:SetText("x")
    local fs = button:GetFontString()
    A.eq(fs:GetTextColor(), 1)
    button:Disable()
    A.same({ fs:GetFont() }, { FONT, 14, "" })
    A.eq(fs:GetTextColor(), 0.5)
    button:Enable()
    A.eq(fs:GetFont(), nil)
  end)
end

return function()
  test_max_lines_and_spacing_change_the_height_assumed()
  test_layout_rect_follows_max_lines_and_spacing_assumed()
  test_max_lines_count_wrapped_lines_assumed()
  test_set_text_height_resizes_the_text_assumed()
  test_getter_defaults()
  test_shadow_defaults_assumed()
  test_setters_round_trip()
  test_shadow_alpha_defaults_to_one_assumed()
  test_font_object_answers_the_getters()
  test_text_settings_inherit_from_the_font_object_assumed()
  test_inheritance_follows_a_chain_of_font_objects_assumed()
  test_edit_box_justify_inherits_from_the_font_object_assumed()
  test_copy_font_object_copies_inherited_settings_assumed()
  test_set_text_height_changes_size_only_assumed()
  test_set_text_height_keeps_an_inherited_file_assumed()
  test_line_height_is_one_line_of_the_current_size_assumed()
  test_unbounded_width_ignores_wrap_assumed()
  test_string_width_includes_truncation_unbounded_does_not_assumed()
  test_wrapped_width_includes_wrap_and_truncation_assumed()
  test_is_truncated_after_max_lines_assumed()
  test_is_truncated_when_a_line_overflows_the_width_assumed()
  test_is_truncated_for_one_word_wider_than_the_width_assumed()
  test_is_truncated_in_a_width_two_anchors_fix_assumed()
  test_text_without_a_fixed_width_is_not_truncated_assumed()
  test_a_replaced_button_text_stops_following_the_state_font_object_assumed()
  test_button_text_follows_the_state_font_object_assumed()
end
