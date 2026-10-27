-- Slider, scroll and panel XML templates (retail, Gethe wow-ui-source branch live, except HorizontalSliderTemplate), same
-- entry shape and `inherits` rule as ui/templates_buttons.lua. Extra fields: flavors = { <flavor> = true } makes an
-- entry exist on those flavors only; orientation is passed to SetOrientation; a child with template = "<Name>" is made
-- from that template (a child that is itself a template element); a child with size = { w, h } gets that size.
-- Not modelled: KeyValues, anchors, texture files, NineSlice layout, and every `function=` script.
local M = {}

M.TEMPLATES = {
  -- source: row W66 (confirmed, classic_era only): Gethe/wow-ui-source 8165d4c,
  -- Interface/AddOns/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml:960, a Slider orientation HORIZONTAL inheriting
  -- BackdropTemplate with a ThumbTexture `Thumb`. The retail extract has no such template (no entry there); the other
  -- classic flavors were not read (row W66), so only vanilla, which is the classic_era branch, has it.
  HorizontalSliderTemplate = {
    type = "Slider",
    inherits = { "BackdropTemplate" },
    children = {
      { key = "Thumb", type = "Texture", adopt = "SetThumbTexture" },
    },
    mixins = {},
    protected = false,
    orientation = "HORIZONTAL",
    flavors = { vanilla = true },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/shared/slider/minimalslider.xml:3-32
  MinimalSliderTemplate = {
    type = "Slider",
    inherits = {},
    children = {
      { key = "Left", type = "Texture" },
      { key = "Right", type = "Texture" },
      { key = "Middle", type = "Texture" },
      { key = "Thumb", type = "Texture", adopt = "SetThumbTexture" },
    },
    mixins = { "MinimalSliderMixin", "NarrationSliderMixin" },
    protected = false,
    size = { 200, 19 },
    orientation = "HORIZONTAL",
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/secureuipaneltemplates.xml:8-14 (the up button of a scroll bar)
  UIPanelScrollUpButtonTemplate = {
    type = "Button",
    inherits = {},
    children = {
      { key = "Normal", type = "Texture", adopt = "SetNormalTexture" },
      { key = "Pushed", type = "Texture", adopt = "SetPushedTexture" },
      { key = "Disabled", type = "Texture", adopt = "SetDisabledTexture" },
      { key = "Highlight", type = "Texture", adopt = "SetHighlightTexture" },
    },
    mixins = {},
    protected = false,
    size = { 18, 16 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/secureuipaneltemplates.xml:16-22 (the down button of a scroll bar)
  UIPanelScrollDownButtonTemplate = {
    type = "Button",
    inherits = {},
    children = {
      { key = "Normal", type = "Texture", adopt = "SetNormalTexture" },
      { key = "Pushed", type = "Texture", adopt = "SetPushedTexture" },
      { key = "Disabled", type = "Texture", adopt = "SetDisabledTexture" },
      { key = "Highlight", type = "Texture", adopt = "SetHighlightTexture" },
    },
    mixins = {},
    protected = false,
    size = { 18, 16 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/securescrolltemplates.xml:7-34 (the scroll bar the scroll frames make)
  UIPanelScrollBarTemplate = {
    type = "Slider",
    inherits = {},
    children = {
      { key = "ScrollUpButton", type = "Button", template = "UIPanelScrollUpButtonTemplate" },
      { key = "ScrollDownButton", type = "Button", template = "UIPanelScrollDownButtonTemplate" },
      { key = "ThumbTexture", type = "Texture", adopt = "SetThumbTexture" },
    },
    mixins = {},
    protected = false,
    size = { 16, 0 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/securescrolltemplates.xml:350-400 (the scroll bar of MinimalScrollFrameTemplate)
  MinimalScrollBarTemplate = {
    type = "Slider",
    inherits = {},
    children = {
      { key = "trackBG", type = "Texture" },
      { key = "ScrollUpButton", type = "Button", template = "UIPanelScrollUpButtonTemplate" },
      { key = "ScrollDownButton", type = "Button", template = "UIPanelScrollDownButtonTemplate" },
      { key = "ThumbTexture", type = "Texture", adopt = "SetThumbTexture" },
    },
    mixins = {},
    protected = false,
    size = { 22, 0 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/secureuipaneltemplates.xml:24-37 (no children, no inherits)
  ScrollFrameTemplate = {
    type = "ScrollFrame",
    inherits = {},
    children = {},
    mixins = {},
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/securescrolltemplates.xml:484-493 over UIPanelScrollFrameCodeTemplate (:36, scripts only)
  MinimalScrollFrameTemplate = {
    type = "ScrollFrame",
    inherits = {},
    children = {
      { key = "ScrollBar", type = "Slider", template = "MinimalScrollBarTemplate" },
    },
    mixins = {},
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/securescrolltemplates.xml:44-53 over UIPanelScrollFrameCodeTemplate (:36, scripts only)
  UIPanelScrollFrameTemplate = {
    type = "ScrollFrame",
    inherits = {},
    children = {
      { key = "ScrollBar", type = "Slider", template = "UIPanelScrollBarTemplate" },
    },
    mixins = {},
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/securescrolltemplates.xml:158-167: the <ScrollChild> is the frame
  FauxScrollFrameTemplate = {
    type = "ScrollFrame",
    inherits = { "UIPanelScrollFrameTemplate" },
    children = {
      { key = "ScrollChildFrame", type = "Frame", adopt = "SetScrollChild", size = { 300, 334 } },
    },
    mixins = {},
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/mainline/shareduipaneltemplates.xml:506-525 over DefaultPanelBaseTemplate (:478-504)
  DefaultPanelTemplate = {
    type = "Frame",
    inherits = {},
    children = {
      { key = "TitleContainer", type = "Frame" },
      { key = "NineSlice", type = "Frame" },
      { key = "Bg", type = "Texture" },
      { key = "TopTileStreaks", type = "Texture" },
    },
    mixins = { "DefaultPanelMixin" },
    protected = false,
    size = { 338, 424 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/mainline/shareduipaneltemplates.xml:445-469
  SimplePanelTemplate = {
    type = "Frame",
    inherits = {},
    children = {
      { key = "Bg", type = "Texture" },
      { key = "Inset", type = "Frame" },
      { key = "NineSlice", type = "Frame" },
    },
    mixins = {},
    protected = false,
    size = { 338, 424 },
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/shared/dialog/dialogtemplates.xml:69-81 over DialogBorderNoCenterTemplate (:63,
  -- NineSlicePanelTemplate: mixin NineSlicePanelMixin)
  DialogBorderTemplate = {
    type = "Frame",
    inherits = {},
    children = {
      { key = "Bg", type = "Texture" },
    },
    mixins = { "NineSlicePanelMixin" },
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/shared/dialog/dialogtemplates.xml:83-95 over DialogBorderNoCenterTemplate
  DialogBorderDarkTemplate = {
    type = "Frame",
    inherits = {},
    children = {
      { key = "Bg", type = "Texture" },
    },
    mixins = { "NineSlicePanelMixin" },
    protected = false,
  },
  -- source: row W66 (confirmed) blizzard_sharedxml/sharedtooltiptemplates.xml:123-127 over TooltipBackdropTemplate (an entry)
  TooltipBorderBackdropTemplate = {
    type = "Frame",
    inherits = { "TooltipBackdropTemplate" },
    children = {},
    mixins = {},
    protected = false,
  },
}

return M
