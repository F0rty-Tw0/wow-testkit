-- The secure templates (retail), same entry shape as ui/templates.lua. A template script that is a function is the kit's own
-- (fn(w, self, ...)); `methods` are the frame methods the template adds. SecureHandler*Template frames are protected and carry
-- Execute, SetFrameRef, WrapScript and UnwrapScript; their scripts run the attribute named for the event as a snippet.
-- source: extract retail 70575 blizzard_framexml/securetemplatesbase.xml (SecureFrameTemplate), securetemplates.xml
-- (SecureActionButtonTemplate, SecureUnitButtonTemplate) and blizzard_restrictedaddonenvironment/securehandlertemplates.xml:6-105
-- (the handler templates; SecureHandlerDoubleClickTemplate is :37-40).
local SecureActions = require("secure_actions")
local SecureHandlers = require("secure_handlers")
local Scripts = require("secure_scripts")

local M = {}

-- inherits Base for the click, drag, show/hide and mouse templates, which add no size of their own.
local function handler(type_, scripts, inherits, size)
  return {
    type = type_,
    inherits = { inherits },
    children = {},
    mixins = {},
    protected = true,
    size = size,
    scripts = scripts,
    methods = SecureHandlers.methods,
  }
end

local SIZE = { 2, 2 }

M.TEMPLATES = {
  SecureFrameTemplate = { type = "Frame", inherits = {}, children = {}, mixins = {}, protected = true },
  SecureActionButtonTemplate = {
    type = "Button",
    inherits = { "SecureFrameTemplate" },
    children = {},
    mixins = { "SecureActionButtonMixin" },
    protected = true,
    scripts = { OnClick = SecureActions.onClick },
  },
  SecureUnitButtonTemplate = {
    type = "Button",
    inherits = { "SecureFrameTemplate" },
    children = {},
    mixins = {},
    protected = true,
    scripts = { OnClick = SecureActions.unitButtonOnClick },
  },
  SecureHandlerBaseTemplate = handler("Frame", nil, "SecureFrameTemplate", SIZE),
  SecureHandlerStateTemplate = handler("Frame", Scripts.scripts.state, "SecureFrameTemplate", SIZE),
  SecureHandlerAttributeTemplate = handler("Frame", Scripts.scripts.attribute, "SecureFrameTemplate", SIZE),
  SecureHandlerClickTemplate = handler("Button", Scripts.scripts.click, "SecureHandlerBaseTemplate"),
  SecureHandlerDoubleClickTemplate = handler("Button", Scripts.scripts.doubleClick, "SecureHandlerBaseTemplate"),
  SecureHandlerDragTemplate = handler("Frame", Scripts.scripts.drag, "SecureHandlerBaseTemplate"),
  SecureHandlerShowHideTemplate = handler("Frame", Scripts.scripts.showHide, "SecureHandlerBaseTemplate"),
  SecureHandlerMouseUpDownTemplate = handler("Frame", Scripts.scripts.mouseUpDown, "SecureHandlerBaseTemplate"),
  SecureHandlerMouseWheelTemplate = handler("Frame", Scripts.scripts.mouseWheel, "SecureHandlerBaseTemplate"),
  SecureHandlerEnterLeaveTemplate = handler("Frame", Scripts.scripts.enterLeave, "SecureHandlerBaseTemplate"),
}

return M
