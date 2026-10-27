-- Button and CheckButton behaviour (ui/behaviour_button.lua): state textures, the button text, the button state, the
-- pushed text offset, font objects per state and the checked textures. Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local A = require("assert")
local Btn = require("ui.behaviour_button")
local HW = require("tests.helpers.widgets")
local Templates = require("ui.templates")

local PATH = "Interface\\Buttons\\WHITE8X8"

local function near(actual, expected)
  A.truthy(math.abs(actual - expected) < 1e-9, string.format("expected %s, got %s", expected, actual))
end

local function newButton()
  return _G.CreateFrame("Button", nil, _G.UIParent)
end

local function test_state_texture_regions_are_the_ones_set() -- W18
  HW.withWidgets("retail", function()
    local b = newButton()
    A.eq(b:GetNormalTexture(), nil)
    b:SetNormalTexture(PATH)
    local n = b:GetNormalTexture()
    A.eq(n:GetObjectType(), "Texture")
    A.eq(n:GetParent(), b)
    A.eq(n:GetTexture(), PATH)
    local own = b:CreateTexture()
    b:SetPushedTexture(own)
    A.eq(b:GetPushedTexture(), own)
    b:ClearNormalTexture()
    A.eq(b:GetNormalTexture(), nil)
    A.eq(n:IsShown(), false)
  end)
end

local function test_a_texture_object_is_reparented_to_the_button() -- W18
  HW.withWidgets("retail", function()
    local b = newButton()
    local other = _G.CreateFrame("Frame", nil, _G.UIParent)
    local own = other:CreateTexture()
    b:SetDisabledTexture(own)
    A.eq(own:GetParent(), b)
    A.eq(b:GetDisabledTexture(), own)
  end)
end

local function test_state_atlas_makes_a_region_with_the_atlas() -- W18
  HW.withWidgets("retail", function()
    local b = newButton()
    b:SetNormalAtlas("common-button")
    b:SetPushedAtlas("common-pushed")
    b:SetHighlightAtlas("common-high")
    b:SetDisabledAtlas("common-off")
    A.same({ b:GetNormalTexture():GetAtlas(), b:GetPushedTexture():GetAtlas() }, { "common-button", "common-pushed" })
    A.same({ b:GetHighlightTexture():GetAtlas(), b:GetDisabledTexture():GetAtlas() }, { "common-high", "common-off" })
  end)
end

local function test_a_path_fills_the_button_assumed() -- W18
  HW.withWidgets("retail", function(w)
    local b = newButton()
    b:SetNormalTexture(PATH)
    local points = w.ui.state[b:GetNormalTexture()].points
    A.same({ points[1][2], points[2][2], #points }, { b, b, 2 })
  end)
end

local function pointTargets(w, texture)
  local points = w.ui.state[texture].points

  return { #points, points[1] and points[1][2], points[2] and points[2][2] }
end

-- source: blizzard_sharedxml/modelscenetemplates.xml:25 draws `<NormalTexture file=.../>` with no Anchors; assumed (W18)
-- a texture object handed over without any anchor fills the button like a path does.
local function test_an_adopted_texture_without_points_fills_the_button_assumed() -- W18
  HW.withWidgets("retail", function(w)
    local b = newButton()
    for _, set in ipairs({ "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture" }) do
      local own = b:CreateTexture()
      b[set](b, own)
      A.same(pointTargets(w, own), { 2, b, b })
    end
    local cb = _G.CreateFrame("CheckButton", nil, _G.UIParent)
    local check = cb:CreateTexture()
    cb:SetCheckedTexture(check)
    A.same(pointTargets(w, check), { 2, cb, cb })
  end)
end

local function test_an_adopted_texture_keeps_its_own_points_assumed() -- W18
  HW.withWidgets("retail", function(w)
    local b = newButton()
    local own = b:CreateTexture()
    own:SetPoint("CENTER")
    b:SetNormalTexture(own)
    A.same({ #w.ui.state[own].points, w.ui.state[own].points[1][1] }, { 1, "CENTER" })
  end)
end

local function test_a_second_path_reuses_the_button_made_region_assumed() -- W18
  HW.withWidgets("retail", function()
    local b = newButton()
    b:SetNormalTexture(PATH)
    local first = b:GetNormalTexture()
    b:SetNormalTexture("Interface\\Other")
    A.eq(b:GetNormalTexture(), first)
    A.eq(first:GetTexture(), "Interface\\Other")
  end)
end

local function test_nil_clears_the_state_texture() -- W18
  HW.withWidgets("retail", function()
    local b = newButton()
    b:SetHighlightTexture(PATH)
    b:SetHighlightTexture(nil)
    A.eq(b:GetHighlightTexture(), nil)
  end)
end

local function test_state_textures_draw_on_artwork_and_the_highlight_on_highlight_assumed() -- W19
  HW.withWidgets("retail", function()
    local b = newButton()
    b:SetNormalTexture(PATH)
    b:SetPushedTexture(PATH)
    b:SetDisabledTexture(PATH)
    b:SetHighlightTexture(b:CreateTexture())
    A.eq(b:GetNormalTexture():GetDrawLayer(), "ARTWORK")
    A.eq(b:GetPushedTexture():GetDrawLayer(), "ARTWORK")
    A.eq(b:GetDisabledTexture():GetDrawLayer(), "ARTWORK")
    A.eq(b:GetHighlightTexture():GetDrawLayer(), "HIGHLIGHT")
  end)
end

local function test_highlight_blend_defaults_to_add_unless_given_assumed() -- W19
  HW.withWidgets("retail", function()
    local b = newButton()
    b:SetHighlightTexture(PATH)
    A.eq(b:GetHighlightTexture():GetBlendMode(), "ADD")
    b:SetHighlightTexture(PATH, "BLEND")
    A.eq(b:GetHighlightTexture():GetBlendMode(), "BLEND")
    local own = b:CreateTexture()
    own:SetBlendMode("MOD")
    b:SetHighlightTexture(own)
    A.eq(own:GetBlendMode(), "MOD")
  end)
end

local function test_fresh_get_text_is_empty() -- W21
  HW.withWidgets("retail", function()
    A.eq(newButton():GetText(), "")
  end)
end

local function test_set_text_creates_the_font_string_assumed() -- W21
  HW.withWidgets("retail", function()
    local b = newButton()
    A.eq(b:GetFontString(), nil)
    b:SetText("Go")
    A.eq(b:GetText(), "Go")
    A.eq(b:GetFontString():GetText(), "Go")
    A.eq(b:GetFontString():GetParent(), b)
  end)
end

local function test_set_text_writes_the_set_font_string() -- W21
  HW.withWidgets("retail", function()
    local b = newButton()
    local fs = b:CreateFontString()
    b:SetFontString(fs)
    b:SetText("Go")
    A.same({ b:GetFontString() == fs, fs:GetText(), b:GetText() }, { true, "Go", "Go" })
  end)
end

local function test_set_formatted_text_goes_to_the_font_string() -- W21
  HW.withWidgets("retail", function()
    local b = newButton()
    b:SetFormattedText("%d/%d", 1, 2)
    A.eq(b:GetFontString():GetText(), "1/2")
  end)
end

local function test_button_state_defaults_assumed() -- W16
  HW.withWidgets("retail", function()
    A.eq(newButton():GetButtonState(), "NORMAL")
  end)
end

local function test_button_state_takes_normal_pushed_and_disabled() -- W16
  HW.withWidgets("retail", function()
    local b = newButton()
    for _, state in ipairs({ "PUSHED", "DISABLED", "NORMAL" }) do
      b:SetButtonState(state)
      A.eq(b:GetButtonState(), state)
    end
    b:SetButtonState("PUSHED", true)
    A.eq(b:GetButtonState(), "PUSHED")
  end)
end

local function test_pushed_text_offset_round_trips() -- W20
  HW.withWidgets("retail", function()
    local b = newButton()
    b:SetPushedTextOffset(2, -3)
    A.same({ b:GetPushedTextOffset() }, { 2, -3 })
  end)
end

local function test_fresh_pushed_text_offset_is_one_minus_one_assumed() -- W20
  HW.withWidgets("retail", function()
    A.same({ newButton():GetPushedTextOffset() }, { 1, -1 })
  end)
end

local function test_font_objects_per_state() -- W22
  HW.withWidgets("retail", function()
    local b = newButton()
    local disabled = _G.CreateFont("T63Disabled")
    A.eq(b:GetNormalFontObject(), nil)
    b:SetDisabledFontObject(disabled)
    A.eq(b:GetDisabledFontObject(), disabled)
    A.eq(b:GetNormalFontObject(), nil)
    A.eq(b:GetHighlightFontObject(), nil)
  end)
end

local function test_a_font_object_name_is_looked_up() -- W22
  HW.withWidgets("retail", function()
    local b = newButton()
    local font = _G.CreateFont("T63Named")
    b:SetNormalFontObject("T63Named")
    A.eq(b:GetNormalFontObject(), font)
  end)
end

local function test_text_width_follows_the_button_text_assumed() -- W23
  HW.withWidgets("retail", function()
    local b = newButton()
    A.same({ b:GetTextWidth(), b:GetTextHeight() }, { 0, 0 })
    b:SetText("abcd")
    A.eq(b:GetTextWidth(), 24)
    near(b:GetTextHeight(), 13.8)
  end)
end

local function test_lock_highlight_round_trips() -- W17
  HW.withWidgets("retail", function()
    local b = newButton()
    A.eq(b:IsHighlightLocked(), false)
    b:LockHighlight()
    A.eq(b:IsHighlightLocked(), true)
    b:UnlockHighlight()
    A.eq(b:IsHighlightLocked(), false)
    b:SetHighlightLocked(true)
    A.eq(b:IsHighlightLocked(), true)
  end)
end

local function test_check_button_checked_textures() -- W24
  HW.withWidgets("retail", function()
    local cb = _G.CreateFrame("CheckButton", nil, _G.UIParent)
    local own = cb:CreateTexture()
    local off = cb:CreateTexture()
    cb:SetCheckedTexture(own)
    cb:SetDisabledCheckedTexture(off)
    A.same({ cb:GetCheckedTexture() == own, cb:GetDisabledCheckedTexture() == off }, { true, true })
    cb:SetCheckedTexture(PATH)
    A.eq(cb:GetCheckedTexture():GetTexture(), PATH)
    A.eq(cb:GetNormalTexture(), nil)
  end)
end

local function test_a_plain_button_has_no_checked_textures() -- W24
  HW.withWidgets("retail", function()
    local b = newButton()
    A.eq(b.SetCheckedTexture, nil)
    A.eq(b.GetDisabledCheckedTexture, nil)
  end)
end

local function test_button_text_font_follows_the_state_assumed() -- W22
  HW.withWidgets("retail", function(w)
    local b = newButton()
    local normal, high, off = _G.CreateFont("T63N"), _G.CreateFont("T63H"), _G.CreateFont("T63D")
    A.eq(Btn.fontFor(w, b), nil)
    b:SetNormalFontObject(normal)
    b:SetHighlightFontObject(high)
    b:SetDisabledFontObject(off)
    A.eq(Btn.fontFor(w, b), normal)
    w.input.mouseFocus = b
    A.eq(Btn.fontFor(w, b), high)
    b:Disable()
    A.eq(Btn.fontFor(w, b), off)
  end)
end

local function test_a_disabled_state_without_a_font_uses_the_normal_one_assumed() -- W22
  HW.withWidgets("retail", function(w)
    local b = newButton()
    local normal = _G.CreateFont("T63Only")
    b:SetNormalFontObject(normal)
    b:Disable()
    A.eq(Btn.fontFor(w, b), normal)
  end)
end

local function test_ui_panel_button_text_is_the_button_font_string() -- W66
  HW.withWidgets("retail", function()
    local b = _G.CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    A.eq(b:GetFontString(), b.Text)
    b:SetText("Go")
    A.eq(b.Text:GetText(), "Go")
  end)
end

local function test_only_the_button_text_children_are_flagged() -- W66
  local flagged = {}
  for name, entry in pairs(Templates.TEMPLATES) do
    for _, child in ipairs(entry.children) do
      if child.buttonText then
        flagged[#flagged + 1] = name .. "." .. child.key
      end
    end
  end
  table.sort(flagged)
  A.same(flagged, { "UIMenuButtonStretchTemplate.Text", "UIPanelButtonTemplate.Text" })
end

return function()
  test_state_texture_regions_are_the_ones_set()
  test_a_texture_object_is_reparented_to_the_button()
  test_state_atlas_makes_a_region_with_the_atlas()
  test_a_path_fills_the_button_assumed()
  test_an_adopted_texture_without_points_fills_the_button_assumed()
  test_an_adopted_texture_keeps_its_own_points_assumed()
  test_a_second_path_reuses_the_button_made_region_assumed()
  test_nil_clears_the_state_texture()
  test_state_textures_draw_on_artwork_and_the_highlight_on_highlight_assumed()
  test_highlight_blend_defaults_to_add_unless_given_assumed()
  test_fresh_get_text_is_empty()
  test_set_text_creates_the_font_string_assumed()
  test_set_text_writes_the_set_font_string()
  test_set_formatted_text_goes_to_the_font_string()
  test_button_state_defaults_assumed()
  test_button_state_takes_normal_pushed_and_disabled()
  test_pushed_text_offset_round_trips()
  test_fresh_pushed_text_offset_is_one_minus_one_assumed()
  test_font_objects_per_state()
  test_a_font_object_name_is_looked_up()
  test_text_width_follows_the_button_text_assumed()
  test_lock_highlight_round_trips()
  test_check_button_checked_textures()
  test_a_plain_button_has_no_checked_textures()
  test_button_text_font_follows_the_state_assumed()
  test_a_disabled_state_without_a_font_uses_the_normal_one_assumed()
  test_ui_panel_button_text_is_the_button_font_string()
  test_only_the_button_text_children_are_flagged()
end
