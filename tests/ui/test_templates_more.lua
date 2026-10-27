-- The built-in templates Phase 6 adds (ui/templates_buttons.lua, ui/templates_panels.lua): type, parentKey children,
-- inherits, flavor, orientation. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local H = require("tests.helpers.render")
local HW = require("tests.helpers.widgets")
local Render = require("render")
local Templates = require("ui.templates")

-- name = { type, keys... }: one line per retail template, every parentKey the W66 row lists plus the ones its
-- inherited templates bring. HorizontalSliderTemplate is not here: retail has no such template (W66).
local EXPECT = {
  ActionButtonTemplate = {
    "CheckButton",
    "icon",
    "IconMask",
    "SlotBackground",
    "SlotArt",
    "Flash",
    "Name",
    "Border",
    "NewActionTexture",
    "SpellHighlightTexture",
    "LevelLinkLockIcon",
    "SpellHighlightAnim",
    "TextOverlayContainer",
    "HotKey",
    "Count",
    "AutoCastOverlay",
    "cooldown",
    "lossOfControlCooldown",
    "chargeCooldown",
    "NormalTexture",
    "PushedTexture",
    "HighlightTexture",
    "CheckedTexture",
  },
  GameMenuButtonTemplate = { "Button", "Left", "Right", "Middle", "Text" },
  MagicButtonTemplate = { "Button", "Left", "Right", "Middle", "Text" },
  SharedButtonTemplate = { "Button", "Left", "Right", "Center", "Controller" },
  UIMenuButtonStretchTemplate = {
    "Button",
    "TopLeft",
    "TopRight",
    "BottomLeft",
    "BottomRight",
    "TopMiddle",
    "MiddleLeft",
    "MiddleRight",
    "BottomMiddle",
    "MiddleMiddle",
    "Text",
  },
  UIPanelButtonGrayTemplate = { "Button" },
  UIPanelDynamicResizeButtonTemplate = { "Button", "Left", "Right", "Middle", "Text" },
  ChatConfigCheckButtonTemplate = { "CheckButton", "Text" },
  InterfaceOptionsCheckButtonTemplate = { "CheckButton", "Text" },
  OptionsBaseCheckButtonTemplate = { "CheckButton", "Text" },
  UIRadioButtonTemplate = { "CheckButton", "text" },
  MinimalSliderTemplate = { "Slider", "Left", "Right", "Middle", "Thumb" },
  ScrollFrameTemplate = { "ScrollFrame" },
  MinimalScrollFrameTemplate = { "ScrollFrame", "ScrollBar" },
  UIPanelScrollFrameTemplate = { "ScrollFrame", "ScrollBar" },
  FauxScrollFrameTemplate = { "ScrollFrame", "ScrollBar", "ScrollChildFrame" },
  DefaultPanelTemplate = { "Frame", "Bg", "TopTileStreaks", "TitleContainer", "NineSlice" },
  SimplePanelTemplate = { "Frame", "Bg", "Inset", "NineSlice" },
  DialogBorderTemplate = { "Frame", "Bg" },
  DialogBorderDarkTemplate = { "Frame", "Bg" },
  TooltipBorderBackdropTemplate = { "Frame", "NineSlice" },
}

local function sortedNames()
  local names = {}
  for name in pairs(EXPECT) do
    names[#names + 1] = name
  end
  table.sort(names)

  return names
end

local function test_every_listed_template_creates_its_type_and_children() -- W66
  HW.withWidgets("retail", function()
    for _, name in ipairs(sortedNames()) do
      local spec = EXPECT[name]
      local frame = _G.CreateFrame(spec[1], nil, _G.UIParent, name)
      A.eq(frame:GetObjectType(), spec[1], name)
      for i = 2, #spec do
        A.truthy(frame[spec[i]], name .. "." .. spec[i])
      end
    end
  end)
end

local function test_the_listed_templates_are_the_w66_rows_less_the_flavor_gated_one() -- W66
  A.eq(#sortedNames(), 21)
end

local function test_no_listed_template_is_reported_unknown() -- W66
  HW.withWidgets("retail", function(w)
    for _, name in ipairs(sortedNames()) do
      _G.CreateFrame(EXPECT[name][1], nil, _G.UIParent, name)
    end
    for key in pairs(w.unscripted) do
      A.eq(key:find("^template:"), nil, key)
    end
  end)
end

local function test_scroll_bar_of_ui_panel_scroll_frame_has_up_and_down_buttons() -- W66
  HW.withWidgets("retail", function()
    local sf = _G.CreateFrame("ScrollFrame", nil, _G.UIParent, "UIPanelScrollFrameTemplate")
    A.eq(sf.ScrollBar:GetObjectType(), "Slider")
    A.eq(sf.ScrollBar.ScrollUpButton:GetObjectType(), "Button")
    A.eq(sf.ScrollBar.ScrollDownButton:GetObjectType(), "Button")
    A.eq(sf.ScrollBar.ScrollUpButton:GetParent(), sf.ScrollBar)
  end)
end

local function test_a_scroll_bar_thumb_is_the_slider_thumb_region() -- W66, W43
  HW.withWidgets("retail", function(w)
    local sf = _G.CreateFrame("ScrollFrame", nil, _G.UIParent, "UIPanelScrollFrameTemplate")
    A.eq(sf.ScrollBar.ThumbTexture:GetObjectType(), "Texture")
    A.eq(w.ui.state[sf.ScrollBar.ThumbTexture].widgetPart, "thumb")
    local minimal = _G.CreateFrame("Slider", nil, _G.UIParent, "MinimalSliderTemplate")
    A.eq(w.ui.state[minimal.Thumb].widgetPart, "thumb")
  end)
end

local function test_a_scroll_bar_is_vertical_and_a_minimal_slider_horizontal() -- W66
  HW.withWidgets("retail", function()
    local sf = _G.CreateFrame("ScrollFrame", nil, _G.UIParent, "UIPanelScrollFrameTemplate")
    A.eq(sf.ScrollBar:GetOrientation(), "VERTICAL")
    A.eq(_G.CreateFrame("Slider", nil, _G.UIParent, "MinimalSliderTemplate"):GetOrientation(), "HORIZONTAL")
  end)
end

local function test_a_faux_scroll_frame_scrolls_its_child_frame() -- W66
  HW.withWidgets("retail", function()
    local sf = _G.CreateFrame("ScrollFrame", nil, _G.UIParent, "FauxScrollFrameTemplate")
    A.eq(sf:GetScrollChild(), sf.ScrollChildFrame)
    A.same({ sf.ScrollChildFrame:GetSize() }, { 300, 334 })
    A.eq(sf.ScrollChildFrame:GetParent(), sf)
  end)
end

local function test_a_template_that_inherits_another_gets_its_children_without_a_copy() -- W66
  HW.withWidgets("retail", function(w)
    local entry = Templates.TEMPLATES.GameMenuButtonTemplate
    A.same(entry.inherits, { "UIPanelButtonTemplate" })
    A.same(entry.children, {})
    local button = _G.CreateFrame("Button", nil, _G.UIParent, "GameMenuButtonTemplate")
    A.eq(button:GetFontString(), button.Text)
    A.same({ button:GetSize() }, { 144, 21 })
    A.same(w.ui.state[button].mixins, { "UIButtonFitToTextBehaviorMixin", "UIPanelButtonMixin" })
  end)
end

local function test_a_derived_template_size_beats_the_inherited_one() -- W66
  HW.withWidgets("retail", function()
    A.same({ _G.CreateFrame("Button", nil, _G.UIParent, "MagicButtonTemplate"):GetSize() }, { 80, 22 })
    A.same({ _G.CreateFrame("CheckButton", nil, _G.UIParent, "OptionsBaseCheckButtonTemplate"):GetSize() }, { 26, 26 })
  end)
end

local function test_magic_button_text_is_the_button_font_string() -- W66, W21
  HW.withWidgets("retail", function()
    local button = _G.CreateFrame("Button", nil, _G.UIParent, "MagicButtonTemplate")
    button:SetText("OK")
    A.eq(button:GetFontString(), button.Text)
    A.eq(button:GetFontString():GetText(), "OK")
  end)
end

local function test_a_menu_button_stretch_text_is_the_button_font_string() -- W66
  HW.withWidgets("retail", function()
    local button = _G.CreateFrame("Button", nil, _G.UIParent, "UIMenuButtonStretchTemplate")
    A.eq(button:GetFontString(), button.Text)
  end)
end

local function test_action_button_state_textures_are_its_children() -- W66, W18
  HW.withWidgets("retail", function()
    local button = _G.CreateFrame("CheckButton", nil, _G.UIParent, "ActionButtonTemplate")
    A.eq(button:GetNormalTexture(), button.NormalTexture)
    A.eq(button:GetPushedTexture(), button.PushedTexture)
    A.eq(button:GetHighlightTexture(), button.HighlightTexture)
    A.eq(button:GetCheckedTexture(), button.CheckedTexture)
  end)
end

local function test_action_button_children_have_the_types_the_xml_names() -- W66
  HW.withWidgets("retail", function()
    local button = _G.CreateFrame("CheckButton", nil, _G.UIParent, "ActionButtonTemplate")
    A.eq(button.IconMask:GetObjectType(), "MaskTexture")
    A.eq(button.SpellHighlightAnim:GetObjectType(), "AnimationGroup")
    A.eq(button.Name:GetObjectType(), "FontString")
    A.eq(button.cooldown:GetObjectType(), "Cooldown")
    A.eq(button.TextOverlayContainer:GetObjectType(), "Frame")
    A.same({ button:GetSize() }, { 45, 45 })
  end)
end

local function test_check_button_templates_have_a_text_font_string() -- W66
  H.withRender(function(w)
    local check = _G.CreateFrame("CheckButton", "CbT", _G.UIParent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("CENTER")
    A.eq(check.Text:GetObjectType(), "FontString")
    check.Text:SetText("Hello")
    local shown = false
    for _, item in ipairs(Render.snapshot(w).items) do
      shown = shown or item.text == "Hello"
    end
    A.truthy(shown)
  end)
end

local function test_template_text_children_are_anchored_as_the_xml_says() -- W66
  HW.withWidgets("retail", function()
    local function anchorOf(kind, template, key)
      local frame = _G.CreateFrame(kind, nil, _G.UIParent, template)
      local point, relativeTo, relativePoint, x, y = frame[key]:GetPoint()
      A.eq(relativeTo, frame, template)

      return { point, relativePoint, x, y }
    end
    A.same(anchorOf("CheckButton", "InterfaceOptionsCheckButtonTemplate", "Text"), { "LEFT", "RIGHT", -2, 0 })
    A.same(anchorOf("CheckButton", "ChatConfigCheckButtonTemplate", "Text"), { "LEFT", "RIGHT", 0, 2 })
    A.same(anchorOf("CheckButton", "UIRadioButtonTemplate", "text"), { "LEFT", "RIGHT", 5, 0 })
    A.same(anchorOf("Button", "UIMenuButtonStretchTemplate", "Text"), { "CENTER", "CENTER", 0, -1 })
  end)
end

local function test_a_button_text_without_anchors_fills_the_button_assumed() -- W66
  HW.withWidgets("retail", function()
    local button = _G.CreateFrame("Button", nil, _G.UIParent, "MagicButtonTemplate")
    A.eq(button.Text:GetNumPoints(), 2)
    local _, relativeTo = button.Text:GetPoint()
    A.eq(relativeTo, button)
  end)
end

return function()
  test_every_listed_template_creates_its_type_and_children()
  test_the_listed_templates_are_the_w66_rows_less_the_flavor_gated_one()
  test_no_listed_template_is_reported_unknown()
  test_scroll_bar_of_ui_panel_scroll_frame_has_up_and_down_buttons()
  test_a_scroll_bar_thumb_is_the_slider_thumb_region()
  test_a_scroll_bar_is_vertical_and_a_minimal_slider_horizontal()
  test_a_faux_scroll_frame_scrolls_its_child_frame()
  test_a_template_that_inherits_another_gets_its_children_without_a_copy()
  test_a_derived_template_size_beats_the_inherited_one()
  test_magic_button_text_is_the_button_font_string()
  test_a_menu_button_stretch_text_is_the_button_font_string()
  test_action_button_state_textures_are_its_children()
  test_action_button_children_have_the_types_the_xml_names()
  test_check_button_templates_have_a_text_font_string()
  test_template_text_children_are_anchored_as_the_xml_says()
  test_a_button_text_without_anchors_fills_the_button_assumed()
end
