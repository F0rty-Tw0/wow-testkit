-- Button items of a render snapshot: the state texture that draws, the highlight, the shifted button text and the
-- exported state. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local H = require("tests.helpers.render")
local Render = require("render")
local S = require("tests.helpers.widget_snap")

-- A Button "Btn" filling the centre of UIParent with a normal, pushed and highlight texture (BtnN, BtnP, BtnH).
local function button()
  local b = S.anchored("Button", "Btn")
  local normal = b:CreateTexture("BtnN")
  normal:SetColorTexture(0, 0, 1)
  b:SetNormalTexture(normal)
  normal:SetAllPoints()
  local pushed = b:CreateTexture("BtnP")
  pushed:SetColorTexture(0, 0, 0.5)
  b:SetPushedTexture(pushed)
  pushed:SetAllPoints()
  local high = b:CreateTexture("BtnH")
  high:SetColorTexture(1, 1, 1, 0.3)
  b:SetHighlightTexture(high)
  high:SetAllPoints()

  return b
end

local function test_only_the_normal_texture_draws_at_rest() -- W17
  H.withRender(function(w)
    button()
    A.same(H.names(Render.snapshot(w), "Btn"), { "Btn", "BtnN" })
  end)
end

local function test_pushed_state_swaps_the_texture_and_exports_state() -- W17
  H.withRender(function(w)
    local b = button()
    b:SetButtonState("PUSHED")
    local snap = Render.snapshot(w)
    A.same(H.names(snap, "Btn"), { "Btn", "BtnP" })
    A.same(H.item(snap, "Btn").widget, { type = "Button", enabled = true, state = "PUSHED" })
  end)
end

local function test_pushed_without_a_pushed_texture_keeps_the_normal_one() -- W17
  H.withRender(function(w)
    local b = S.anchored("Button", "Bare")
    local normal = b:CreateTexture("BareN")
    normal:SetColorTexture(0, 0, 1)
    b:SetNormalTexture(normal)
    normal:SetAllPoints()
    b:SetButtonState("PUSHED")
    A.same(H.names(Render.snapshot(w), "Bare"), { "Bare", "BareN" })
  end)
end

local function test_highlight_draws_when_hovered_or_locked() -- W17
  H.withRender(function(w)
    local b = button()
    b:LockHighlight()
    local snap = Render.snapshot(w)
    A.same(H.names(snap, "Btn"), { "Btn", "BtnN", "BtnH" })
    A.same(H.item(snap, "Btn").widget, { type = "Button", enabled = true, locked = true })
    b:UnlockHighlight()
    w.input.mouseFocus = b
    A.same(H.names(Render.snapshot(w), "Btn"), { "Btn", "BtnN", "BtnH" })
  end)
end

local function test_button_text_is_a_font_string_shifted_while_pushed() -- W20, W21
  H.withRender(function(w)
    local b = S.anchored("Button", "TBtn")
    local fs = b:CreateFontString("TBtnText")
    fs:SetAllPoints(b)
    b:SetFontString(fs)
    b:SetPushedTextOffset(1, -1)
    b:SetText("Go")
    A.same(H.rect(Render.snapshot(w), "TBtnText"), { x = 910, y = 515, width = 100, height = 50 })
    b:SetButtonState("PUSHED")
    A.same(H.rect(Render.snapshot(w), "TBtnText"), { x = 911, y = 516, width = 100, height = 50 })
    b:SetPushedTextOffset(3, -2)
    A.same(H.rect(Render.snapshot(w), "TBtnText"), { x = 913, y = 517, width = 100, height = 50 })
  end)
end

local function test_pushed_state_shifts_only_the_button_text() -- W20
  H.withRender(function(w)
    local b = button()
    local other = b:CreateFontString("TOther")
    other:SetAllPoints(b)
    other:SetText("Other")
    b:SetButtonState("PUSHED")
    A.same(H.rect(Render.snapshot(w), "TOther"), { x = 910, y = 515, width = 100, height = 50 })
    A.same(H.rect(Render.snapshot(w), "BtnP"), { x = 910, y = 515, width = 100, height = 50 })
  end)
end

local function test_disabled_button_shows_its_disabled_texture_or_the_normal_one() -- W17
  H.withRender(function(w)
    local b = button()
    b:Disable()
    A.same(H.names(Render.snapshot(w), "Btn"), { "Btn", "BtnN" })
    local disabled = b:CreateTexture("BtnD")
    disabled:SetColorTexture(0.5, 0.5, 0.5)
    b:SetDisabledTexture(disabled)
    disabled:SetAllPoints()
    A.same(H.names(Render.snapshot(w), "Btn"), { "Btn", "BtnD" })
    w.input.mouseFocus = b
    A.same(H.names(Render.snapshot(w), "Btn"), { "Btn", "BtnD" })
  end)
end

local function test_checked_texture_draws_while_checked_and_enabled_assumed() -- W24
  H.withRender(function(w)
    local cb = S.anchored("CheckButton", "Chk")
    local on = cb:CreateTexture("ChkOn")
    on:SetColorTexture(0, 1, 0)
    cb:SetCheckedTexture(on)
    on:SetAllPoints()
    local off = cb:CreateTexture("ChkOff")
    off:SetColorTexture(0.5, 0.5, 0.5)
    cb:SetDisabledCheckedTexture(off)
    off:SetAllPoints()
    A.same(H.names(Render.snapshot(w), "Chk"), { "Chk" })
    cb:SetChecked(true)
    A.same(H.names(Render.snapshot(w), "Chk"), { "Chk", "ChkOn" })
    cb:Disable()
    A.same(H.names(Render.snapshot(w), "Chk"), { "Chk", "ChkOff" })
    A.same(H.item(Render.snapshot(w), "Chk").widget, { type = "CheckButton", checked = true, enabled = false })
  end)
end

local function test_button_text_made_by_set_text_fills_the_button_assumed() -- W21
  H.withRender(function(w)
    local b = S.anchored("Button", "Made")
    b:SetText("Go")
    local made = {}
    for _, item in ipairs(Render.snapshot(w).items) do
      if item.kind == "fontstring" then
        made[#made + 1] = item.rect
      end
    end
    A.same(made, { { x = 910, y = 515, width = 100, height = 50 } })
  end)
end

local function test_set_font_string_on_a_pushed_button_shifts_the_text() -- W20
  H.withRender(function(w)
    local b = S.anchored("Button", "Late")
    local fs = b:CreateFontString("LateText")
    fs:SetAllPoints(b)
    fs:SetText("Go")
    b:SetButtonState("PUSHED")
    A.same(H.rect(Render.snapshot(w), "LateText"), { x = 910, y = 515, width = 100, height = 50 })
    b:SetFontString(fs)
    A.same(H.rect(Render.snapshot(w), "LateText"), { x = 911, y = 516, width = 100, height = 50 })
  end)
end

local function test_fresh_button_widget_shape_is_unchanged()
  H.withRender(function(w)
    S.anchored("Button", "Plain")
    A.same(S.snap(w, "Plain").widget, { type = "Button", enabled = true })
  end)
end

return function()
  test_only_the_normal_texture_draws_at_rest()
  test_pushed_state_swaps_the_texture_and_exports_state()
  test_pushed_without_a_pushed_texture_keeps_the_normal_one()
  test_highlight_draws_when_hovered_or_locked()
  test_button_text_is_a_font_string_shifted_while_pushed()
  test_pushed_state_shifts_only_the_button_text()
  test_disabled_button_shows_its_disabled_texture_or_the_normal_one()
  test_checked_texture_draws_while_checked_and_enabled_assumed()
  test_button_text_made_by_set_text_fills_the_button_assumed()
  test_set_font_string_on_a_pushed_button_shifts_the_text()
  test_fresh_button_widget_shape_is_unchanged()
end
