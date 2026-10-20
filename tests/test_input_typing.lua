-- Input actions on an EditBox: type and press.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")
local Rec = require("tests.helpers.input")

local withFrameXML = HF.withFrameXML
local ELLIPSIS = "\226\128\166"

local function newBox(name)
  return _G.CreateFrame("EditBox", name, _G.UIParent)
end

local function test_type_fires_on_char_then_on_text_changed_per_character() -- (I8)
  withFrameXML("retail", function(w)
    local box = newBox()
    local log = Rec.record(box, { "OnChar", "OnTextChanged" })
    Input.type(w, box, "ab")
    A.same(log, { { "OnChar", "a" }, { "OnTextChanged", true }, { "OnChar", "b" }, { "OnTextChanged", true } })
    A.eq(box:GetText(), "ab")
  end)
end

local function test_type_keeps_a_multibyte_character_whole()
  withFrameXML("retail", function(w)
    local box = newBox()
    local chars, texts = {}, {}
    box:SetScript("OnChar", function(self, char)
      chars[#chars + 1] = char
      texts[#texts + 1] = self:GetText()
    end)
    Input.type(w, box, "a" .. ELLIPSIS .. "b")
    A.same(chars, { "a", ELLIPSIS, "b" })
    A.eq(#chars[2], 3)
    A.same(texts, { "a", "a" .. ELLIPSIS, "a" .. ELLIPSIS .. "b" })
  end)
end

local function test_type_focuses_the_box_and_bypasses_set_text()
  withFrameXML("retail", function(w)
    local box = newBox()
    local log = Rec.record(box, { "OnEditFocusGained", "OnTextSet" })
    Input.type(w, box, "hi")
    A.same(log, { { "OnEditFocusGained" } })
    A.eq(box:HasFocus(), true)
  end)
end

local function test_press_fires_the_key_script()
  withFrameXML("retail", function(w)
    local box = newBox()
    local log = Rec.record(box, { "OnEnterPressed", "OnEscapePressed", "OnTabPressed" })
    box:SetFocus()
    Input.press(w, box, "ENTER")
    Input.press(w, box, "ESCAPE")
    Input.press(w, box, "TAB")
    A.same(log, { { "OnEnterPressed" }, { "OnEscapePressed" }, { "OnTabPressed" } })
  end)
end

local function test_press_unknown_key_is_a_usage_error()
  withFrameXML("retail", function(w)
    local box = newBox()
    box:SetFocus()
    A.errors(function()
      Input.press(w, box, "F5")
    end, "press: unknown key 'F5'")
  end)
end

local function test_press_without_focus_throws()
  withFrameXML("retail", function(w)
    local box = newBox("Box")
    A.errors(function()
      Input.press(w, box, "ENTER")
    end, "press: Box does not have focus")
  end)
end

return function()
  test_type_fires_on_char_then_on_text_changed_per_character()
  test_type_keeps_a_multibyte_character_whole()
  test_type_focuses_the_box_and_bypasses_set_text()
  test_press_fires_the_key_script()
  test_press_unknown_key_is_a_usage_error()
  test_press_without_focus_throws()
end
