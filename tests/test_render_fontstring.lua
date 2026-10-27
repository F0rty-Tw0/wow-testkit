-- FontString fields of a render item that come from the text settings getters (ui/behaviour_fontstring.lua): a font
-- object value shows, and `truncated` appears only for truncated text. Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local A = require("assert")
local H = require("tests.helpers.render")
local Render = require("render")
local S = require("tests.helpers.widget_snap")

local FONT = "Fonts\\FRIZQT__.TTF"

-- A font string "Str" of size 10 in a retail render world; fn gets it and a function that returns its item.
local function withText(fn)
  H.withRender(function(w)
    local frame = S.anchored("Frame", "Host")
    local fs = frame:CreateFontString("Str")
    fs:SetFont(FONT, 10, "")
    fs:SetText("aaaa bbbb cccc")
    fs:SetPoint("CENTER")
    fn(fs, function()
      return H.item(Render.snapshot(w), "Str")
    end)
  end)
end

local function test_font_object_values_show_in_the_item_assumed() -- W31
  withText(function(fs, read)
    local font = _G.CreateFont("T64Render")
    font:SetJustifyH("LEFT")
    font:SetJustifyV("TOP")
    font:SetSpacing(3)
    font:SetShadowColor(1, 0, 0, 1)
    font:SetShadowOffset(2, -2)
    fs:SetFontObject(font)
    local item = read()
    A.eq(item.justifyH, "LEFT")
    A.eq(item.justifyV, "TOP")
    A.eq(item.spacing, 3)
    A.same(item.shadow, { color = { 1, 0, 0, 1 }, x = 2, y = -2 })
  end)
end

local function test_own_value_beats_the_font_object_assumed() -- W31
  withText(function(fs, read)
    local font = _G.CreateFont("T64RenderOwn")
    font:SetJustifyH("LEFT")
    fs:SetFontObject(font)
    fs:SetJustifyH("RIGHT")
    A.eq(read().justifyH, "RIGHT")
  end)
end

local function test_truncated_only_when_text_is_truncated_assumed() -- W26
  withText(function(fs, read)
    fs:SetWidth(30)
    A.eq(read().truncated, nil)
    fs:SetMaxLines(1)
    A.eq(read().truncated, true)
    fs:SetMaxLines(0)
    A.eq(read().truncated, nil)
  end)
end

local function test_item_height_follows_max_lines_and_spacing_assumed() -- W28
  withText(function(fs, read)
    fs:SetWidth(30)
    fs:SetSpacing(2)
    A.eq(read().rect.height, 38.5)
    fs:SetMaxLines(2)
    A.eq(read().rect.height, 25)
  end)
end

local function test_button_text_item_uses_the_state_font_object_assumed() -- W22
  H.withRender(function(w)
    local off = _G.CreateFont("T64RenderOff")
    off:SetFont(FONT, 14, "OUTLINE")
    off:SetTextColor(0.5, 0.5, 0.5)
    local button = S.anchored("Button", "Btn")
    button:SetDisabledFontObject(off)
    button:SetText("x")
    button:Disable()
    local text
    for _, item in ipairs(Render.snapshot(w).items) do
      text = item.kind == "fontstring" and item or text
    end
    A.eq(text.size, 14)
    A.eq(text.flags, "OUTLINE")
    A.same(text.color, { 0.5, 0.5, 0.5, 1 })
  end)
end

return function()
  test_font_object_values_show_in_the_item_assumed()
  test_own_value_beats_the_font_object_assumed()
  test_truncated_only_when_text_is_truncated_assumed()
  test_item_height_follows_max_lines_and_spacing_assumed()
  test_button_text_item_uses_the_state_font_object_assumed()
end
