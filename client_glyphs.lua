-- Text width from an extracted glyph table (tools/client/fonts.py): the advance of each character in font units plus the
-- kerning between neighbours, scaled to the font size. Colour and link escapes take no room and textures keep their own
-- width (ui/measure.lua scanLine); that the font flags (outline, thick) do not change the width is assumed.
local M = {}

local Measure = require("ui.measure")

-- Same shift as tools/client/fonts.py KERN_SHIFT: kern[left * KERN_SHIFT + right], codepoints being under it.
M.KERN_SHIFT = 0x200000

local MIN_TWO_BYTE_LEAD, MIN_THREE_BYTE_LEAD, MIN_FOUR_BYTE_LEAD, MAX_LEAD = 0xC2, 0xE0, 0xF0, 0xF4
local CONTINUATION_BITS = 6
local FIRST_CONTINUATION, LAST_CONTINUATION = 0x80, 0xBF

-- Codepoint and byte length of the UTF-8 character at pos; nil and 1 for a stray or truncated byte.
local function decode(text, pos)
  local lead = text:byte(pos)
  if lead < 0x80 then
    return lead, 1
  elseif lead < MIN_TWO_BYTE_LEAD or lead > MAX_LEAD then
    return nil, 1
  end
  local length = lead >= MIN_FOUR_BYTE_LEAD and 4 or lead >= MIN_THREE_BYTE_LEAD and 3 or 2
  local codepoint = lead % (2 ^ (7 - length))
  for offset = 1, length - 1 do
    local byte = text:byte(pos + offset)
    if not (byte and byte >= FIRST_CONTINUATION and byte <= LAST_CONTINUATION) then
      return nil, 1
    end
    codepoint = codepoint * 2 ^ CONTINUATION_BITS + byte % 2 ^ CONTINUATION_BITS
  end
  return codepoint, length
end

-- Font units of a run of visible text.
local function runUnits(glyphs, text)
  local units, previous, pos = 0, nil, 1
  while pos <= #text do
    local codepoint, length = decode(text, pos)
    units = units + (codepoint and glyphs.advance[codepoint] or glyphs.notdef)
    if previous and codepoint then
      units = units + (glyphs.kern[previous * M.KERN_SHIFT + codepoint] or 0)
    end
    previous = codepoint
    pos = pos + length
  end
  return units
end

-- Width of one line at size; glyphs is a table loaded from fonts/glyphs/<name>.lua.
function M.width(glyphs, size, _, text)
  return Measure.scanLine(text, size, function(run)
    return runUnits(glyphs, run) * size / glyphs.upm
  end)
end

return M
