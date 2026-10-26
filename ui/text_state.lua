-- The text settings of a FontString or Font as the client answers them, read from kit state without calling a method
-- of the region. SetJustifyH/V, SetSpacing, SetShadowColor and SetShadowOffset store into st.values (the generic
-- store); a region that never set one reads it from its font object chain. SetMaxLines and SetWordWrap belong to the
-- FontString alone and do not inherit.
local M = {}

local FontChain = require("ui.font_chain")

-- source: xsd:505-509 and xsd:762-769 (`spacing` 0, `justifyV` MIDDLE, `justifyH` CENTER, `wordwrap` true, `maxLines` 0);
-- same values as V11. That a CreateFontString object has the same defaults is assumed (V11).
M.JUSTIFY_H = "CENTER"
M.JUSTIFY_V = "MIDDLE"
M.SPACING = 0
M.MAX_LINES = 0

-- The st.values keys a region reads through its font object chain.
M.INHERITED_KEYS = { "JustifyH", "JustifyV", "Spacing", "ShadowColor", "ShadowOffset" }

local DEFAULT_ALPHA = 1

local function first(pack, default)
  return pack and pack[1] or default
end

function M.justifyH(w, st)
  return first(FontChain.value(w, st, "JustifyH"), M.JUSTIFY_H)
end

function M.justifyV(w, st)
  return first(FontChain.value(w, st, "JustifyV"), M.JUSTIFY_V)
end

function M.spacing(w, st)
  return first(FontChain.value(w, st, "Spacing"), M.SPACING)
end

function M.maxLines(st)
  return first(st.values.MaxLines, M.MAX_LINES)
end

-- True unless SetWordWrap turned it off.
function M.wordWrap(st)
  local pack = st.values.WordWrap

  return pack == nil or (pack[1] and true or false)
end

-- source: assumed (W29) the shadow colour is 0, 0, 0, 0 until set; SetShadowColor without alpha means 1 (a nilable
-- argument, api SimpleFontStringAPI.lua SetShadowColor).
-- The stored { r, g, b, a } list, or nil when neither this region nor its font object chain set one.
function M.shadowColor(w, st)
  local pack = FontChain.value(w, st, "ShadowColor")

  return pack and { pack[1], pack[2], pack[3], pack[4] or DEFAULT_ALPHA }
end

-- source: assumed (W29) the shadow offset is 0, 0 until set. The stored { x, y } list, or nil when never set.
function M.shadowOffset(w, st)
  local pack = FontChain.value(w, st, "ShadowOffset")

  return pack and { pack[1], pack[2] }
end

return M
