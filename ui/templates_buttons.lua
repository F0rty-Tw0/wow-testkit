-- Button-family XML templates (retail, Gethe wow-ui-source branch live), same entry shape as ui/templates.lua. A
-- template whose `inherits` names an entry here or there gets that entry applied first (ui/template_apply.lua), so it
-- lists only its own children; an inherited template the kit has no entry for is flattened into the entry. A child
-- with adopt = "<Setter>" is passed to that frame method after it is made (the button state textures).
-- anchor = { point, relativePoint, x, y } anchors the child to the frame it is made on.
-- Not modelled: KeyValues, the <NormalFont>/<HighlightFont>/<DisabledFont> styles, <PushedTextOffset>, other anchors,
-- texture files, and every `function=` script (Blizzard Lua the kit does not load).
local M = {}

M.TEMPLATES = {
  -- source: row W66 (confirmed) blizzard_actionbar/mainline/actionbuttontemplate.xml:4-170, with the children of
  -- ActionButtonSpellFXTemplate (blizzard_actionbar/shared/actionbuttoncomponenttemplate.xml:328) and
  -- FlyoutButtonTemplate (blizzard_flyout/flyout.xml:3). HotKey and Count are children of TextOverlayContainer in the
  -- XML and ActionButtonTextOverlayContainerMixin:OnLoad copies them onto the button
  -- (blizzard_actionbar/shared/actionbutton.lua:1825); the row lists them on the button, so they are made there.
  ActionButtonTemplate = {
    type = "CheckButton",
    inherits = {},
    children = {
      { key = "InterruptDisplay", type = "Frame" },
      { key = "SpellCastAnimFrame", type = "Frame" },
      { key = "TargetReticleAnimFrame", type = "Frame" },
      { key = "CooldownFlash", type = "Frame" },
      { key = "BorderShadow", type = "Texture" },
      { key = "Arrow", type = "Texture" },
      { key = "icon", type = "Texture" },
      { key = "IconMask", type = "MaskTexture" },
      { key = "SlotBackground", type = "Texture" },
      { key = "SlotArt", type = "Texture" },
      { key = "Flash", type = "Texture" },
      { key = "Name", type = "FontString" },
      { key = "Border", type = "Texture" },
      { key = "NewActionTexture", type = "Texture" },
      { key = "SpellHighlightTexture", type = "Texture" },
      { key = "LevelLinkLockIcon", type = "Texture" },
      { key = "SpellHighlightAnim", type = "AnimationGroup" },
      { key = "TextOverlayContainer", type = "Frame" },
      { key = "HotKey", type = "FontString" },
      { key = "Count", type = "FontString" },
      { key = "AutoCastOverlay", type = "Frame" },
      { key = "cooldown", type = "Cooldown" },
      { key = "lossOfControlCooldown", type = "Cooldown" },
      { key = "chargeCooldown", type = "Cooldown" },
      { key = "NormalTexture", type = "Texture", adopt = "SetNormalTexture" },
      { key = "PushedTexture", type = "Texture", adopt = "SetPushedTexture" },
      { key = "HighlightTexture", type = "Texture", adopt = "SetHighlightTexture" },
      { key = "CheckedTexture", type = "Texture", adopt = "SetCheckedTexture" },
    },
    mixins = { "FlyoutButtonMixin", "PingableType_ActionButtonMixin", "BaseActionButtonMixin" },
    protected = false,
    size = { 45, 45 },
  },
  -- source: row W66 (confirmed) blizzard_uipaneltemplates/mainline/uipaneltemplates.xml:11-16
  GameMenuButtonTemplate = {
    type = "Button",
    inherits = { "UIPanelButtonTemplate" },
    children = {},
    mixins = {},
    protected = false,
    size = { 144, 21 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/mainline/shareduipaneltemplates.xml:722-727
  MagicButtonTemplate = {
    type = "Button",
    inherits = { "UIPanelButtonTemplate" },
    children = {},
    mixins = {},
    protected = false,
    size = { 80, 22 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/shared/button/threeslicebuttontemplate.xml:69-74: BigRedThreeSliceButtonTemplate
  -- (:60, size 441x128) over ThreeSliceButtonTemplate (:3, mixin ThreeSliceButtonMixin, size 20x20), neither an entry.
  SharedButtonTemplate = {
    type = "Button",
    inherits = {},
    children = {
      { key = "Left", type = "Texture" },
      { key = "Right", type = "Texture" },
      { key = "Center", type = "Texture" },
      { key = "Controller", type = "Frame" },
    },
    mixins = { "ThreeSliceButtonMixin" },
    protected = false,
    size = { 200, 30 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/mainline/shareduipaneltemplates.xml:745-838
  UIMenuButtonStretchTemplate = {
    type = "Button",
    inherits = {},
    children = {
      { key = "TopLeft", type = "Texture" },
      { key = "TopRight", type = "Texture" },
      { key = "BottomLeft", type = "Texture" },
      { key = "BottomRight", type = "Texture" },
      { key = "TopMiddle", type = "Texture" },
      { key = "MiddleLeft", type = "Texture" },
      { key = "MiddleRight", type = "Texture" },
      { key = "BottomMiddle", type = "Texture" },
      { key = "MiddleMiddle", type = "Texture" },
      { key = "Text", type = "FontString", buttonText = true, anchor = { "CENTER", "CENTER", 0, -1 } },
    },
    mixins = { "UIMenuButtonStretchMixin" },
    protected = false,
    size = { 40, 26 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/mainline/shareduipaneltemplates.xml:895-903 (no size, no children)
  UIPanelButtonGrayTemplate = {
    type = "Button",
    inherits = {},
    children = {},
    mixins = {},
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/shared/button/uipanelbuttontemplates.xml:12-23
  UIPanelDynamicResizeButtonTemplate = {
    type = "Button",
    inherits = { "UIPanelButtonTemplate" },
    children = {},
    mixins = {},
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_chatframe/mainline/chatconfigframe.xml:109-121 over ChatConfigBaseCheckButtonTemplate
  -- (:73, size 32x32; no entry). The element's parentKey="CheckButton" names it when it is a child of another element.
  ChatConfigCheckButtonTemplate = {
    type = "CheckButton",
    inherits = {},
    children = {
      { key = "Text", type = "FontString", anchor = { "LEFT", "RIGHT", 0, 2 } },
    },
    mixins = {},
    protected = false,
    size = { 24, 24 },
  },
  -- source: row W66 (confirmed) blizzard_framexml/deprecatedtemplates.xml:34 (an empty element)
  InterfaceOptionsCheckButtonTemplate = {
    type = "CheckButton",
    inherits = { "OptionsBaseCheckButtonTemplate" },
    children = {},
    mixins = {},
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_framexml/deprecatedtemplates.xml:5-17: no keyed children of its own; the `Text`
  -- comes from UICheckButtonTemplate (blizzard_sharedxml/shared/button/checkbuttontemplates.xml:50).
  OptionsBaseCheckButtonTemplate = {
    type = "CheckButton",
    inherits = { "UICheckButtonTemplate" },
    children = {},
    mixins = {},
    protected = false,
    size = { 26, 26 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/shared/button/checkbuttontemplates.xml:4-25
  UIRadioButtonTemplate = {
    type = "CheckButton",
    inherits = {},
    children = {
      { key = "text", type = "FontString", anchor = { "LEFT", "RIGHT", 5, 0 } },
    },
    mixins = {},
    protected = false,
    size = { 16, 16 },
  },
}

return M
