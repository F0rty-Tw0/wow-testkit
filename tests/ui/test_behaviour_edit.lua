-- EditBox behaviour (ui/behaviour_edit.lua): the cursor, selection, typing limits, numeric and password boxes, multi-line
-- Enter, history lines and text insets. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local HW = require("tests.helpers.widgets")
local Input = require("input")
local Keys = require("input_keys")
local Rec = require("tests.helpers.input")

local ELLIPSIS = "\226\128\166"

local function newBox()
  return _G.CreateFrame("EditBox", nil, _G.UIParent)
end

local function test_insert_goes_at_the_cursor() -- W33
  HW.withWidgets("retail", function()
    local box = newBox()
    box:SetText("ac")
    box:SetCursorPosition(1)
    box:Insert("b")
    A.same({ box:GetText(), box:GetCursorPosition() }, { "abc", 2 })
  end)
end

local function test_numeric_box_ignores_letters_and_reads_numbers() -- W36
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetNumeric(true)
    Input.type(w, box, "1a2b")
    A.same({ box:GetText(), box:GetNumber(), box:IsNumeric() }, { "12", 12, true })
  end)
end

local function test_numeric_box_strips_the_decimal_point() -- W36
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetNumeric(true)
    Input.type(w, box, "1.5")
    A.eq(box:GetText(), "15")
  end)
end

local function test_typing_stops_at_max_letters_assumed() -- W35
  HW.withWidgets("retail", function(w)
    local box = newBox()
    A.eq(box:GetMaxLetters(), 0)
    box:SetMaxLetters(3)
    Input.type(w, box, "abcdef")
    A.eq(box:GetText(), "abc")
    box:SetText("abcdefg")
    A.same({ box:GetText(), box:GetMaxLetters() }, { "abcdefg", 3 })
  end)
end

local function test_max_letters_counts_characters_not_bytes_assumed() -- W35
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetMaxLetters(2)
    Input.type(w, box, ELLIPSIS .. ELLIPSIS .. "a")
    A.eq(box:GetText(), ELLIPSIS .. ELLIPSIS)
  end)
end

local function test_a_refused_character_fires_no_script_assumed() -- W35
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetMaxLetters(1)
    Input.type(w, box, "a")
    local log = Rec.record(box, { "OnChar", "OnTextChanged" })
    Input.type(w, box, "b")
    A.same(log, {})
  end)
end

local function test_cursor_defaults_clamps_and_follows_set_text_assumed() -- W32
  HW.withWidgets("retail", function()
    local box = newBox()
    A.eq(box:GetCursorPosition(), 0)
    box:SetText("abc")
    A.eq(box:GetCursorPosition(), 3)
    box:SetCursorPosition(99)
    A.eq(box:GetCursorPosition(), 3)
    box:SetCursorPosition(1)
    A.eq(box:GetCursorPosition(), 1)
    box:SetCursorPosition(-4)
    A.eq(box:GetCursorPosition(), 0)
  end)
end

local function test_typing_moves_the_cursor_after_the_character_assumed() -- W32
  HW.withWidgets("retail", function(w)
    local box = newBox()
    Input.type(w, box, "ac")
    box:SetCursorPosition(1)
    Input.type(w, box, ELLIPSIS)
    A.same({ box:GetText(), box:GetCursorPosition() }, { "a" .. ELLIPSIS .. "c", 2 })
  end)
end

local function test_set_text_moves_the_cursor_before_the_scripts_run_assumed() -- W32
  HW.withWidgets("retail", function()
    local box = newBox()
    local seen
    box:SetScript("OnTextSet", function(self)
      seen = self:GetCursorPosition()
    end)
    box:SetText("abcd")
    A.eq(seen, 4)
  end)
end

local function test_set_number_and_empty_number() -- W36
  HW.withWidgets("retail", function()
    local box = newBox()
    A.eq(box:GetNumber(), 0)
    box:SetNumber(7)
    A.same({ box:GetText(), box:GetNumber(), box:GetCursorPosition() }, { "7", 7, 1 })
    box:SetText("12abc")
    A.eq(box:GetNumber(), 12)
    box:SetText("abc")
    A.eq(box:GetNumber(), 0)
  end)
end

local function test_password_box_hides_display_text_only_assumed() -- W37
  HW.withWidgets("retail", function()
    local box = newBox()
    box:SetPassword(true)
    box:SetText("abc")
    A.same({ box:GetText(), box:GetDisplayText(), box:IsPassword() }, { "abc", "***", true })
    box:SetPassword(false)
    A.eq(box:GetDisplayText(), "abc")
  end)
end

local function test_password_display_counts_characters_assumed() -- W37
  HW.withWidgets("retail", function()
    local box = newBox()
    box:SetPassword(true)
    box:SetText(ELLIPSIS .. "a")
    A.eq(box:GetDisplayText(), "**")
  end)
end

local function test_highlight_selects_and_typing_replaces() -- W34
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetText("abcd")
    box:HighlightText(1, 3)
    Input.type(w, box, "X")
    A.same({ box:GetText(), box:GetCursorPosition() }, { "aXd", 2 })
    box:HighlightText()
    Input.type(w, box, "Z")
    A.eq(box:GetText(), "Z")
  end)
end

local function test_set_cursor_position_drops_the_selection_assumed() -- W32
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetText("abcd")
    box:HighlightText(0, 4)
    box:SetCursorPosition(1)
    Input.type(w, box, "X")
    A.eq(box:GetText(), "aXbcd")
  end)
end

local function test_insert_replaces_the_selection_and_honours_the_limits_assumed() -- W33
  HW.withWidgets("retail", function()
    local box = newBox()
    box:SetText("abcd")
    box:HighlightText(1, 3)
    box:Insert("XY")
    A.same({ box:GetText(), box:GetCursorPosition() }, { "aXYd", 3 })
    box:SetNumeric(true)
    box:SetText("")
    box:Insert("1a2")
    A.eq(box:GetText(), "12")
    box:SetMaxLetters(3)
    box:Insert("345")
    A.eq(box:GetText(), "123")
  end)
end

local function test_insert_fires_no_script_assumed() -- W33
  HW.withWidgets("retail", function()
    local box = newBox()
    local log = Rec.record(box, { "OnChar", "OnTextChanged", "OnTextSet" })
    box:Insert("a")
    A.same(log, {})
  end)
end

local function test_highlight_one_argument_runs_to_the_end() -- W34
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetText("abcd")
    box:HighlightText(2)
    Input.type(w, box, "X")
    A.eq(box:GetText(), "abX")
    box:SetText("abcd")
    box:HighlightText(1, -1)
    Input.type(w, box, "Y")
    A.eq(box:GetText(), "aY")
  end)
end

local function test_an_empty_highlight_selects_nothing_assumed() -- W34
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetText("abcd")
    box:HighlightText(2, 2)
    Input.type(w, box, "X")
    A.eq(box:GetText(), "abcdX")
  end)
end

local function test_backspace_at_the_start_removes_nothing_assumed() -- W32
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetText("abc")
    box:SetCursorPosition(0)
    local log = Rec.record(box, { "OnTextChanged" })
    box:SetFocus()
    Keys.press(w, "BACKSPACE")
    A.same({ box:GetText(), box:GetCursorPosition(), log }, { "abc", 0, {} })
  end)
end

local function test_an_edit_clears_the_selection_assumed() -- W34
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetText("abcd")
    box:HighlightText(1, 3)
    box:SetText("xy")
    Input.type(w, box, "Q")
    A.eq(box:GetText(), "xyQ")
  end)
end

local function test_typing_over_a_selection_makes_room_for_max_letters_assumed() -- W34
  HW.withWidgets("retail", function(w)
    local box = newBox()
    box:SetText("abc")
    box:SetMaxLetters(3)
    box:HighlightText(0, 1)
    Input.type(w, box, "XY")
    A.eq(box:GetText(), "Xbc")
  end)
end

local function test_multi_line_enter_inserts_a_newline_assumed() -- W38
  HW.withWidgets("retail", function(w)
    local box = newBox()
    A.eq(box:IsMultiLine(), false)
    box:SetMultiLine(true)
    Input.type(w, box, "a")
    local log = Rec.record(box, { "OnEnterPressed" })
    Keys.press(w, "ENTER")
    A.same({ box:GetText(), box:GetCursorPosition(), log }, { "a\n", 2, {} })
  end)
end

local function test_single_line_enter_fires_the_script() -- W38
  HW.withWidgets("retail", function(w)
    local box = newBox()
    Input.type(w, box, "a")
    local log = Rec.record(box, { "OnEnterPressed" })
    Keys.press(w, "ENTER")
    A.same({ box:GetText(), log }, { "a", { { "OnEnterPressed" } } })
  end)
end

local function test_backspace_deletes_before_the_cursor_assumed() -- W32
  HW.withWidgets("retail", function(w)
    local box = newBox()
    Input.type(w, box, "abc")
    box:SetCursorPosition(2)
    Keys.press(w, "BACKSPACE")
    A.same({ box:GetText(), box:GetCursorPosition() }, { "ac", 1 })
    box:HighlightText(0, 2)
    Keys.press(w, "BACKSPACE")
    A.same({ box:GetText(), box:GetCursorPosition() }, { "", 0 })
  end)
end

local function test_history_lines_is_the_maximum_not_the_stored_count_assumed() -- W40
  HW.withWidgets("retail", function()
    local box = newBox()
    A.eq(box:GetHistoryLines(), 0)
    box:AddHistoryLine("x")
    box:AddHistoryLine("y")
    A.eq(box:GetHistoryLines(), 0)
    box:SetHistoryLines(5)
    A.eq(box:GetHistoryLines(), 5)
  end)
end

local function test_text_insets_default_zero_and_are_stored_assumed() -- W41
  HW.withWidgets("retail", function()
    local box = newBox()
    A.same({ box:GetTextInsets() }, { 0, 0, 0, 0 })
    box:SetTextInsets(1, 2, 3, 4)
    A.same({ box:GetTextInsets() }, { 1, 2, 3, 4 })
  end)
end

local function test_auto_focus_defaults_true_and_show_does_not_focus_assumed() -- W39
  HW.withWidgets("retail", function()
    local box = newBox()
    A.eq(box:IsAutoFocus(), true)
    box:Show()
    A.eq(box:HasFocus(), false)
    box:SetAutoFocus(false)
    A.eq(box:IsAutoFocus(), false)
  end)
end

return function()
  test_insert_goes_at_the_cursor()
  test_numeric_box_ignores_letters_and_reads_numbers()
  test_numeric_box_strips_the_decimal_point()
  test_typing_stops_at_max_letters_assumed()
  test_max_letters_counts_characters_not_bytes_assumed()
  test_a_refused_character_fires_no_script_assumed()
  test_cursor_defaults_clamps_and_follows_set_text_assumed()
  test_typing_moves_the_cursor_after_the_character_assumed()
  test_set_text_moves_the_cursor_before_the_scripts_run_assumed()
  test_set_number_and_empty_number()
  test_password_box_hides_display_text_only_assumed()
  test_password_display_counts_characters_assumed()
  test_highlight_selects_and_typing_replaces()
  test_highlight_one_argument_runs_to_the_end()
  test_set_cursor_position_drops_the_selection_assumed()
  test_insert_replaces_the_selection_and_honours_the_limits_assumed()
  test_insert_fires_no_script_assumed()
  test_an_empty_highlight_selects_nothing_assumed()
  test_backspace_at_the_start_removes_nothing_assumed()
  test_an_edit_clears_the_selection_assumed()
  test_typing_over_a_selection_makes_room_for_max_letters_assumed()
  test_multi_line_enter_inserts_a_newline_assumed()
  test_single_line_enter_fires_the_script()
  test_backspace_deletes_before_the_cursor_assumed()
  test_history_lines_is_the_maximum_not_the_stored_count_assumed()
  test_text_insets_default_zero_and_are_stored_assumed()
  test_auto_focus_defaults_true_and_show_does_not_focus_assumed()
end
