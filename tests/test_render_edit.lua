-- EditBox fields of a render item's widget (render_widgets.lua): the display text, selection, password flag, insets and
-- justify, each shown only when it differs from a fresh box. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local H = require("tests.helpers.render")
local S = require("tests.helpers.widget_snap")

local FRESH = { type = "EditBox", text = "", cursor = 0, focused = false, multiLine = false }

local function test_a_fresh_box_exports_the_phase_two_shape()
  H.withRender(function(w)
    S.anchored("EditBox", "Fresh")
    A.same(S.snap(w, "Fresh").widget, FRESH)
  end)
end

local function test_password_box_exports_the_masked_text_assumed() -- W37
  H.withRender(function(w)
    local box = S.anchored("EditBox", "Pass")
    box:SetPassword(true)
    box:SetText("abc")
    local widget = S.snap(w, "Pass").widget
    A.same({ widget.text, widget.password }, { "***", true })
  end)
end

local function test_highlight_exports_the_selection() -- W34
  H.withRender(function(w)
    local box = S.anchored("EditBox", "Sel")
    box:SetText("abcd")
    box:HighlightText(1, 3)
    A.same(S.snap(w, "Sel").widget.selection, { from = 1, to = 3 })
  end)
end

local function test_insets_export_only_when_not_all_zero_assumed() -- W41
  H.withRender(function(w)
    local box = S.anchored("EditBox", "Ins")
    box:SetTextInsets(0, 0, 0, 0)
    A.eq(S.snap(w, "Ins").widget.insets, nil)
    box:SetTextInsets(1, 2, 3, 4)
    A.same(S.snap(w, "Ins").widget.insets, { l = 1, r = 2, t = 3, b = 4 })
  end)
end

local function test_justify_exports_only_when_not_left_assumed()
  H.withRender(function(w)
    local box = S.anchored("EditBox", "Just")
    box:SetJustifyH("LEFT")
    A.eq(S.snap(w, "Just").widget.justifyH, nil)
    box:SetJustifyH("RIGHT")
    A.eq(S.snap(w, "Just").widget.justifyH, "RIGHT")
  end)
end

local function test_justify_from_a_font_object_exports()
  H.withRender(function(w)
    local font = _G.CreateFont("T65EditFont")
    font:SetJustifyH("CENTER")
    local box = S.anchored("EditBox", "FontJust")
    box:SetFontObject(font)
    A.eq(S.snap(w, "FontJust").widget.justifyH, "CENTER")
  end)
end

return function()
  test_a_fresh_box_exports_the_phase_two_shape()
  test_password_box_exports_the_masked_text_assumed()
  test_highlight_exports_the_selection()
  test_insets_export_only_when_not_all_zero_assumed()
  test_justify_exports_only_when_not_left_assumed()
  test_justify_from_a_font_object_exports()
end
