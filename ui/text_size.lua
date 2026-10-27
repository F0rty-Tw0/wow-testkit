-- The size of a FontString's text, in its own units: ui/measure.lua on the text and font read from kit state (the font
-- object chain, size 12 when none), with the line limit and spacing of ui/text_state.lua. Nothing here calls a method
-- of the region, so an addon override cannot run inside a layout resolve. A retail secret text measures as the text it
-- hides (combat_secret_value.lua).
local M = {}

local FontChain = require("ui.font_chain")
local Measure = require("ui.measure")
local Secret = require("combat_secret_value")
local TextState = require("ui.text_state")

-- file, size, flags of the font st shows.
local function fontOf(w, st)
  local font = FontChain.inherited(w, st, "font") or {}

  return font[1], tonumber(font[2]) or Measure.DEFAULT_FONT_SIZE, font[3]
end

-- source: row LY10 is assumed (no source states the rule); W28 is assumed: max lines clamp the height to that many
-- lines and spacing adds `spacing` between consecutive lines. The width counts the first max-lines paragraphs, the
-- height the first max-lines lines of the text wrapped at wrap (nil = one line per paragraph); nil for a region
-- that is not a FontString.
function M.of(w, region, axis, wrap)
  local st = w.ui.state[region]
  if not (st and st.plan.isA.fontstring) then
    return nil
  end
  local file, size, flags = fontOf(w, st)
  local maxLines = TextState.maxLines(st)
  if axis == "x" then
    return Measure.width(w, file, size, flags, Secret.text(st.text), maxLines)
  end
  local count = Measure.lineCount(w, file, size, flags, Secret.text(st.text), wrap)
  local lines = maxLines > 0 and math.min(maxLines, count) or count

  return lines * size * Measure.LINE_HEIGHT + (lines - 1) * TextState.spacing(w, st)
end

-- source: confirmed (W30) wiki API_FontString_GetUnboundedStringWidth: "GetUnboundedStringWidth() ignores word wrap and
-- truncation". The widest paragraph of the whole text.
function M.unbounded(w, region)
  local st = w.ui.state[region]
  local file, size, flags = fontOf(w, st)

  return Measure.width(w, file, size, flags, Secret.text(st.text))
end

-- source: confirmed (W30) wiki API_FontString_GetUnboundedStringWidth: "GetWrappedWidth() includes word wrap and
-- truncation". The widest line of the text wrapped at wrap (nil = no wrap) within the max lines.
function M.wrapped(w, region, wrap)
  local st = w.ui.state[region]
  local file, size, flags = fontOf(w, st)

  return Measure.wrappedWidth(w, file, size, flags, Secret.text(st.text), wrap, TextState.maxLines(st))
end

-- source: assumed (W26) text is truncated when max lines hid some of it, or when a line is wider than the fixed width
-- (wrap is the wrap width, nil with word wrap off; fixedWidth nil when the width comes from the text).
function M.isTruncated(w, region, wrap, fixedWidth)
  local st = w.ui.state[region]
  local file, size, flags = fontOf(w, st)
  local maxLines = TextState.maxLines(st)
  if maxLines > 0 and Measure.lineCount(w, file, size, flags, Secret.text(st.text), wrap) > maxLines then
    return true
  end

  return fixedWidth ~= nil and Measure.wrappedWidth(w, file, size, flags, Secret.text(st.text), wrap, maxLines) > fixedWidth
end

-- source: assumed (W25) one line of the current size, with no spacing.
function M.lineHeight(w, region)
  local _, size = fontOf(w, w.ui.state[region])

  return size * Measure.LINE_HEIGHT
end

return M
