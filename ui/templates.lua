-- XML template facts for CreateFrame's template argument: retail (Gethe wow-ui-source, branch live) only.
-- Per template: Ketho Templates.lua type, direct inherits and mixin names (flattened over the inherits
-- chain), the parentKey children (key and widget type) flattened over the inherits chain from the XML, the
-- XML <Size> (most derived wins), protected for Secure* templates, and scripts (handler name -> the mixin method the
-- XML's method="" names, for the few handlers the kit models). Facts only: no Blizzard XML or Lua.
-- The comment above each entry lists the inherits chain and the XML file that defines each link.
-- Templates in use by the reference addons (WhisperMessenger, RaidGroupWrap, MouseOverTooltip), 2026-10-04.
local M = {}

M.TEMPLATES = {
  -- Blizzard_SharedXML/Backdrop.xml: BackdropTemplate
  BackdropTemplate = {
    type = "Frame",
    inherits = {},
    children = {},
    mixins = { "BackdropTemplateMixin" },
    protected = false,
  },
  -- Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml: BaseBasicFrameTemplate, BasicFrameTemplate, BasicFrameTemplateWithInset
  BasicFrameTemplateWithInset = {
    type = "Frame",
    inherits = { "BasicFrameTemplate" },
    children = {
      { key = "TopLeftCorner", type = "Texture" },
      { key = "TopRightCorner", type = "Texture" },
      { key = "TopBorder", type = "Texture" },
      { key = "TitleText", type = "FontString" },
      { key = "BotLeftCorner", type = "Texture" },
      { key = "BotRightCorner", type = "Texture" },
      { key = "BottomBorder", type = "Texture" },
      { key = "LeftBorder", type = "Texture" },
      { key = "RightBorder", type = "Texture" },
      { key = "CloseButton", type = "Button" },
      { key = "Bg", type = "Texture" },
      { key = "TitleBg", type = "Texture" },
      { key = "TopTileStreaks", type = "Texture" },
      { key = "InsetBg", type = "Texture" },
      { key = "InsetBorderTopLeft", type = "Texture" },
      { key = "InsetBorderTopRight", type = "Texture" },
      { key = "InsetBorderBottomLeft", type = "Texture" },
      { key = "InsetBorderBottomRight", type = "Texture" },
      { key = "InsetBorderTop", type = "Texture" },
      { key = "InsetBorderBottom", type = "Texture" },
      { key = "InsetBorderLeft", type = "Texture" },
      { key = "InsetBorderRight", type = "Texture" },
    },
    mixins = {},
    protected = false,
  },
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: PortraitFrameBaseTemplate, ButtonFrameBaseTemplate, ButtonFrameTemplate
  ButtonFrameTemplate = {
    type = "Frame",
    inherits = { "ButtonFrameBaseTemplate" },
    children = {
      { key = "NineSlice", type = "Frame" },
      { key = "PortraitContainer", type = "Frame" },
      { key = "TitleContainer", type = "Frame" },
      { key = "Bg", type = "Texture" },
      { key = "TopTileStreaks", type = "Texture" },
      { key = "CloseButton", type = "Button" },
      { key = "Inset", type = "Frame" },
    },
    mixins = { "PortraitFrameMixin" },
    protected = false,
    size = { 338, 424 },
  },
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: NineSliceCodeTemplate, NineSlicePanelTemplate
  -- Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml: DialogBorderNoCenterTemplate, DialogBorderTranslucentTemplate
  DialogBorderTranslucentTemplate = {
    type = "Frame",
    inherits = { "DialogBorderNoCenterTemplate" },
    children = {
      { key = "Bg", type = "Texture" },
    },
    mixins = { "NineSlicePanelMixin" },
    protected = false,
  },
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: InsetFrameTemplate
  InsetFrameTemplate = {
    type = "Frame",
    inherits = {},
    children = {
      { key = "Bg", type = "Texture" },
      { key = "NineSlice", type = "Frame" },
    },
    mixins = {},
    protected = false,
  },
  -- Blizzard_SharedXML/Shared/Slider/MinimalSlider.xml: MinimalSliderWithSteppersTemplate
  MinimalSliderWithSteppersTemplate = {
    type = "Frame",
    inherits = {},
    children = {
      { key = "Slider", type = "Slider" },
      { key = "Back", type = "Button" },
      { key = "Forward", type = "Button" },
      { key = "LeftText", type = "FontString" },
      { key = "RightText", type = "FontString" },
      { key = "TopText", type = "FontString" },
      { key = "MinText", type = "FontString" },
      { key = "MaxText", type = "FontString" },
    },
    mixins = { "MinimalSliderWithSteppersMixin" },
    protected = false,
    size = { 250, 40 },
  },
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: UISliderTemplate, UISliderTemplateWithLabels
  -- Blizzard_FrameXML/DeprecatedTemplates.xml: OptionsSliderTemplate
  OptionsSliderTemplate = {
    type = "Slider",
    inherits = { "UISliderTemplateWithLabels" },
    children = {
      { key = "NineSlice", type = "Frame" },
      { key = "Thumb", type = "Texture" },
      { key = "Text", type = "FontString" },
      { key = "Low", type = "FontString" },
      { key = "High", type = "FontString" },
    },
    mixins = {},
    protected = false,
    size = { 144, 17 },
  },
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: PanelTabButtonTemplate
  PanelTabButtonTemplate = {
    type = "Button",
    inherits = {},
    children = {
      { key = "LeftActive", type = "Texture" },
      { key = "RightActive", type = "Texture" },
      { key = "MiddleActive", type = "Texture" },
      { key = "Left", type = "Texture" },
      { key = "Right", type = "Texture" },
      { key = "Middle", type = "Texture" },
      { key = "LeftHighlight", type = "Texture" },
      { key = "MiddleHighlight", type = "Texture" },
      { key = "RightHighlight", type = "Texture" },
      { key = "Text", type = "FontString" },
    },
    mixins = { "PanelTabButtonMixin" },
    protected = false,
    size = { 10, 32 },
  },
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: PortraitFrameBaseTemplate, PortraitFrameTexturedBaseTemplate, PortraitFrameTemplateNoCloseButton, PortraitFrameTemplate
  PortraitFrameTemplate = {
    type = "Frame",
    inherits = { "PortraitFrameTemplateNoCloseButton" },
    children = {
      { key = "NineSlice", type = "Frame" },
      { key = "PortraitContainer", type = "Frame" },
      { key = "TitleContainer", type = "Frame" },
      { key = "Bg", type = "Texture" },
      { key = "TopTileStreaks", type = "Texture" },
      { key = "CloseButton", type = "Button" },
    },
    mixins = { "PortraitFrameMixin" },
    protected = false,
    size = { 338, 424 },
  },
  -- Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml: InputBoxScriptTemplate, InputBoxVisualTemplate, InputBoxTemplate, InputBoxInstructionsTemplate, SearchBoxTemplate
  SearchBoxTemplate = {
    type = "EditBox",
    inherits = { "InputBoxInstructionsTemplate" },
    children = {
      { key = "Left", type = "Texture" },
      { key = "Right", type = "Texture" },
      { key = "Middle", type = "Texture" },
      { key = "Instructions", type = "FontString" },
      { key = "searchIcon", type = "Texture" },
      { key = "clearButton", type = "Button" },
    },
    mixins = { "NarrationEditBoxMixin", "NarrationSearchBoxMixin" },
    protected = false,
  },
  -- Blizzard_FrameXML/SecureTemplatesBase.xml: SecureFrameTemplate
  -- Blizzard_FrameXML/SecureTemplates.xml: SecureActionButtonTemplate
  SecureActionButtonTemplate = {
    type = "Button",
    inherits = { "SecureFrameTemplate" },
    children = {},
    mixins = { "SecureActionButtonMixin" },
    protected = true,
  },
  -- Blizzard_SharedXML/SharedTooltipTemplates.xml: TooltipBackdropTemplate
  TooltipBackdropTemplate = {
    type = "Frame",
    inherits = {},
    children = {
      { key = "NineSlice", type = "Frame" },
    },
    mixins = { "TooltipBackdropTemplateMixin" },
    protected = false,
  },
  -- Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml: UICheckButtonArtTemplate, UICheckButtonTemplate
  UICheckButtonTemplate = {
    type = "CheckButton",
    inherits = { "UICheckButtonArtTemplate" },
    children = {
      { key = "Text", type = "FontString" },
    },
    mixins = {},
    protected = false,
    size = { 32, 32 },
  },
  -- Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml: UIDropDownMenuTemplate
  UIDropDownMenuTemplate = {
    type = "Frame",
    inherits = {},
    children = {
      { key = "Left", type = "Texture" },
      { key = "Middle", type = "Texture" },
      { key = "Right", type = "Texture" },
      { key = "Text", type = "FontString" },
      { key = "Icon", type = "Texture" },
      { key = "Button", type = "Button" }, -- intrinsic <DropDownToggleButton>, a Button
    },
    mixins = {},
    protected = false,
    size = { 40, 32 },
  },
  -- Blizzard_SharedXML/SecureUIPanelTemplates.xml: UIPanelButtonNoTooltipTemplate
  -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: UIPanelButtonTemplate
  UIPanelButtonTemplate = {
    type = "Button",
    inherits = { "UIPanelButtonNoTooltipTemplate" },
    children = {
      { key = "Left", type = "Texture" },
      { key = "Right", type = "Texture" },
      { key = "Middle", type = "Texture" },
      { key = "Text", type = "FontString" },
    },
    mixins = { "UIButtonFitToTextBehaviorMixin", "UIPanelButtonMixin" },
    protected = false,
    size = { 40, 22 },
  },
  -- source: confirmed (row D7) Blizzard_Menu/Mainline/MenuTemplates.xml:3-39: WowStyle1DropdownTemplate (no inherits; the element is the intrinsic
  -- DropdownButton). Mainline values: 120x25, Text is GameFontHighlight, justifyH LEFT. Blizzard_Menu/Classic/MenuTemplates.xml
  -- has the same keys and types at 60x24 with GameFontHighlightSmall and RIGHT; the flavorless entry takes Mainline's.
  -- scripts: <OnLoad method="OnLoad"/> (Mainline :30, Classic :33) and <OnShow method="OnShow"/> (Mainline :31, Classic :34);
  -- WowStyle1DropdownMixin.OnLoad checks the frame is a DropdownButton (Blizzard_Menu/MenuTemplates.lua:931-932), OnShow
  -- is self:GenerateMenu() (:816-820). The template's other scripts are not modelled.
  WowStyle1DropdownTemplate = {
    type = "DropdownButton",
    inherits = {},
    children = {
      { key = "Background", type = "Texture" },
      { key = "Arrow", type = "Texture" },
      { key = "Text", type = "FontString" },
    },
    mixins = { "WowStyle1DropdownMixin" },
    protected = false,
    size = { 120, 25 },
    scripts = { OnLoad = "OnLoad", OnShow = "OnShow" },
  },
}

return M
