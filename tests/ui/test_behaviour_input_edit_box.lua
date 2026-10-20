-- EditBox input methods: focus and text.
local A = require("assert")
local HW = require("tests.helpers.widgets")
local Rec = require("tests.helpers.input")

local withWidgets = HW.withWidgets

local function test_set_focus_moves_focus_and_fires_lost_then_gained()
  withWidgets("retail", function(w)
    local a, b = _G.CreateFrame("EditBox"), _G.CreateFrame("EditBox")
    local log = Rec.record(a, { "OnEditFocusGained", "OnEditFocusLost" }, nil, "a")
    Rec.record(b, { "OnEditFocusGained", "OnEditFocusLost" }, log, "b")
    a:SetFocus()
    b:SetFocus()
    A.same(log, { { "a:OnEditFocusGained" }, { "a:OnEditFocusLost" }, { "b:OnEditFocusGained" } })
    A.eq(a:HasFocus(), false)
    A.eq(b:HasFocus(), true)
    A.eq(w.input.editFocus, b)
  end)
end

local function test_focus_state_is_current_when_the_handlers_run()
  withWidgets("retail", function()
    local a, b = _G.CreateFrame("EditBox"), _G.CreateFrame("EditBox")
    local seen = {}
    a:SetScript("OnEditFocusLost", function(self)
      seen.lost = self:HasFocus()
    end)
    b:SetScript("OnEditFocusGained", function(self)
      seen.gained = self:HasFocus()
    end)
    a:SetFocus()
    b:SetFocus()
    A.same(seen, { lost = false, gained = true })
  end)
end

local function test_set_focus_on_the_focused_box_fires_nothing()
  withWidgets("retail", function()
    local a = _G.CreateFrame("EditBox")
    local log = Rec.record(a, { "OnEditFocusGained", "OnEditFocusLost" })
    a:SetFocus()
    a:SetFocus()
    A.same(log, { { "OnEditFocusGained" } })
  end)
end

local function test_clear_focus_fires_lost_and_clears_only_for_the_focused_box()
  withWidgets("retail", function(w)
    local a, b = _G.CreateFrame("EditBox"), _G.CreateFrame("EditBox")
    local logA = Rec.record(a, { "OnEditFocusLost" })
    local logB = Rec.record(b, { "OnEditFocusLost" })
    a:SetFocus()
    b:ClearFocus()
    A.same(logB, {})
    A.eq(a:HasFocus(), true)
    a:ClearFocus()
    A.same(logA, { { "OnEditFocusLost" } })
    A.eq(w.input.editFocus, nil)
  end)
end

local function test_set_text_on_an_edit_box_fires_on_text_changed_with_user_input_false() -- (I6)
  withWidgets("retail", function()
    local box = _G.CreateFrame("EditBox")
    local log = Rec.record(box, { "OnTextSet", "OnTextChanged" })
    box:SetText("hi")
    A.eq(box:GetText(), "hi")
    A.same(log, { { "OnTextSet" }, { "OnTextChanged", false } }) -- (I6 confirmed: OnTextSet fires before OnTextChanged)
  end)
end

local function test_set_text_with_the_same_text_fires_no_on_text_changed() -- (I6)
  withWidgets("retail", function()
    local box = _G.CreateFrame("EditBox")
    box:SetText("hi")
    local log = Rec.record(box, { "OnTextChanged" })
    box:SetText("hi")
    A.same(log, {})
  end)
end

local function test_set_text_of_empty_text_on_a_fresh_box_fires_no_on_text_changed() -- (I6)
  withWidgets("retail", function()
    local box = _G.CreateFrame("EditBox")
    local log = Rec.record(box, { "OnTextChanged" })
    box:SetText("")
    box:SetText()
    A.same(log, {})
  end)
end

local function test_set_text_with_the_same_text_still_fires_on_text_set_assumed() -- (I6)
  withWidgets("retail", function()
    local box = _G.CreateFrame("EditBox")
    box:SetText("hi")
    local log = Rec.record(box, { "OnTextSet" })
    box:SetText("hi")
    A.same(log, { { "OnTextSet" } })
  end)
end

local function test_on_text_changed_that_sets_its_own_text_does_not_recurse() -- (I6)
  withWidgets("retail", function(w)
    local box = _G.CreateFrame("EditBox")
    local calls = 0
    -- the shape of Blizzard's ColorPickerHexBoxMixin:OnTextChanged (row I6)
    box:SetScript("OnTextChanged", function(self)
      calls = calls + 1
      self:SetText((self:GetText():gsub("[^A-Fa-f0-9]", "")))
    end)
    box:SetText("ab-c")
    A.eq(box:GetText(), "abc")
    A.eq(calls, 2)
    A.eq(#w.errors, 0)
  end)
end

-- The doc's EditBox GetText return is not nilable (api/<flavor>/SimpleEditBoxAPI.lua GetText, every flavor). (I12)
local function test_get_text_of_a_fresh_edit_box_is_empty()
  withWidgets("retail", function()
    local box = _G.CreateFrame("EditBox")
    A.eq(box:GetText(), "")
    box:SetText(nil)
    A.eq(box:GetText(), "")
  end)
end

local function test_set_text_on_other_types_is_unchanged()
  withWidgets("retail", function()
    local fontString = _G.CreateFrame("Frame"):CreateFontString()
    fontString:SetText("x")
    A.eq(fontString:GetText(), "x")
    local button = _G.CreateFrame("Button")
    button:SetText("y")
    A.eq(button:GetText(), "y")
  end)
end

return function()
  test_set_focus_moves_focus_and_fires_lost_then_gained()
  test_focus_state_is_current_when_the_handlers_run()
  test_set_focus_on_the_focused_box_fires_nothing()
  test_clear_focus_fires_lost_and_clears_only_for_the_focused_box()
  test_set_text_on_an_edit_box_fires_on_text_changed_with_user_input_false()
  test_set_text_with_the_same_text_fires_no_on_text_changed()
  test_set_text_of_empty_text_on_a_fresh_box_fires_no_on_text_changed()
  test_set_text_with_the_same_text_still_fires_on_text_set_assumed()
  test_on_text_changed_that_sets_its_own_text_does_not_recurse()
  test_get_text_of_a_fresh_edit_box_is_empty()
  test_set_text_on_other_types_is_unchanged()
end
