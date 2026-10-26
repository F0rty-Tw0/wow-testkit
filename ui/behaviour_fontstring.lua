-- Hand-written FontString and font object behaviour. The setters (SetJustifyH/V, SetWordWrap, SetMaxLines, SetSpacing,
-- SetShadowColor, SetShadowOffset) stay generic and store into st.values; the getters read them through ui/text_state.lua
-- (a region that never set one reads its font object's) and the sizes come from ui/text_size.lua. The getters register
-- through Typed.add for "fontinstance" (FontString, Font, EditBox ...), the FontString-only methods for "fontstring",
-- so M.methods stays empty. Methods are fn(w, obj, st, ...) like ui/behaviour.lua.
local M = {}

local FontChain = require("ui.font_chain")
local Layout = require("ui.layout")
local TextSize = require("ui.text_size")
local TextState = require("ui.text_state")
local Typed = require("ui.typed")

local unpack = unpack

M.methods = {}

local SHADOW_COLOR_FIELDS = 4
local NO_SHADOW_COLOR = { 0, 0, 0, 0 }
local NO_SHADOW_OFFSET = { 0, 0 }

-- True when the text of obj is truncated (ui/text_size.lua isTruncated): ui/render_fields.lua exports it too.
function M.isTruncated(w, obj)
  return TextSize.isTruncated(w, obj, Layout.wrapWidth(w, obj), Layout.fixedWidth(w, obj))
end

local function getJustifyH(w, _, st)
  return TextState.justifyH(w, st)
end

local function getJustifyV(w, _, st)
  return TextState.justifyV(w, st)
end

local function getSpacing(w, _, st)
  return TextState.spacing(w, st)
end

local function getShadowColor(w, _, st)
  return unpack(TextState.shadowColor(w, st) or NO_SHADOW_COLOR, 1, SHADOW_COLOR_FIELDS)
end

local function getShadowOffset(w, _, st)
  return unpack(TextState.shadowOffset(w, st) or NO_SHADOW_OFFSET)
end

local function getLineHeight(w, obj)
  return TextSize.lineHeight(w, obj)
end

local function canWordWrap(_, _, st)
  return TextState.wordWrap(st)
end

local function isTruncated(w, obj)
  return M.isTruncated(w, obj)
end

-- source: confirmed (W30) wiki API_FontString_GetUnboundedStringWidth: "GetStringWidth() ignores word wrap but includes
-- truncation"; "GetUnboundedStringWidth() ignores word wrap and truncation"; "GetWrappedWidth() includes word wrap and
-- truncation"; api/retail/SimpleFontStringAPI.lua:467 GetUnboundedStringWidth, :504 GetWrappedWidth.
-- (GetStringWidth is ui/behaviour_text.lua: the widest of the first max-lines paragraphs.)
local function getUnboundedStringWidth(w, obj)
  return TextSize.unbounded(w, obj)
end

local function getWrappedWidth(w, obj)
  return TextSize.wrapped(w, obj, Layout.wrapWidth(w, obj))
end

-- source: assumed (W27) the size changes and the font file and flags stay, wherever the font came from.
local function setTextHeight(w, _, st, height)
  local font = FontChain.inherited(w, st, "font") or {}
  st.font = { font[1], height, font[3] }
end

local FONT_INSTANCE_METHODS = {
  GetJustifyH = getJustifyH,
  GetJustifyV = getJustifyV,
  GetSpacing = getSpacing,
  GetShadowColor = getShadowColor,
  GetShadowOffset = getShadowOffset,
}
for name, impl in pairs(FONT_INSTANCE_METHODS) do
  Typed.add(name, "fontinstance", impl)
end

local FONT_STRING_METHODS = {
  GetLineHeight = getLineHeight,
  CanWordWrap = canWordWrap,
  IsTruncated = isTruncated,
  GetUnboundedStringWidth = getUnboundedStringWidth,
  GetWrappedWidth = getWrappedWidth,
  SetTextHeight = setTextHeight,
}
for name, impl in pairs(FONT_STRING_METHODS) do
  Typed.add(name, "fontstring", impl)
end

return M
