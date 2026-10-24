-- Text measurement. Fallback estimate until glyph tables exist (Measure.useGlyphs): each visible character is
-- AVERAGE_ADVANCE * size wide, a line is LINE_HEIGHT * size tall. Color codes (|cAARRGGBB, |r) are invisible and a
-- UTF-8 character counts once. Both ratios are assumed (row LY10, ruling R2).
local M = {}

M.AVERAGE_ADVANCE = 0.5
M.LINE_HEIGHT = 1.15
M.DEFAULT_FONT_SIZE = 12

local COLOR_START = "|c%x%x%x%x%x%x%x%x"
local COLOR_END = "|r"
local UTF8_LEAD_BYTE = "[^\128-\191]"

-- Stores per-font glyph tables: tables[fontFile].width(size, flags, text) then measures a line of that font.
function M.useGlyphs(w, tables)
  w.measure = { glyphs = tables }
end

local function visibleCharCount(text)
  local visible = text:gsub(COLOR_START, ""):gsub(COLOR_END, "")
  local _, count = visible:gsub(UTF8_LEAD_BYTE, "")
  return count
end

local function lineWidth(w, fontFile, size, flags, line)
  local glyphs = w.measure and fontFile and w.measure.glyphs[fontFile]
  if glyphs then
    return glyphs.width(size, flags, line)
  end
  return visibleCharCount(line) * M.AVERAGE_ADVANCE * size
end

-- "\n" and "|n" both end a paragraph; empty text is one empty paragraph.
local function paragraphs(text)
  local list = {}
  for paragraph in (tostring(text or ""):gsub("|n", "\n") .. "\n"):gmatch("(.-)\n") do
    list[#list + 1] = paragraph
  end
  return list
end

-- Greedy wrap at spaces: a word joins the line while the line stays within wrapWidth; a word wider than wrapWidth
-- keeps a line of its own (no mid-word break). Returns the lines.
local function wrap(w, fontFile, size, flags, paragraph, wrapWidth)
  local lines, current = {}, nil
  for word in paragraph:gmatch("[^ ]+") do
    local candidate = current and (current .. " " .. word) or word
    if current and lineWidth(w, fontFile, size, flags, candidate) > wrapWidth then
      lines[#lines + 1] = current
      current = word
    else
      current = candidate
    end
  end
  lines[#lines + 1] = current or ""
  return lines
end

-- Width of the widest line; wrapping does not change it.
function M.width(w, fontFile, size, flags, text)
  local widest = 0
  for _, paragraph in ipairs(paragraphs(text)) do
    widest = math.max(widest, lineWidth(w, fontFile, size, flags, paragraph))
  end
  return widest
end

-- Lines * size * LINE_HEIGHT; with wrapWidth > 0 each paragraph wraps, without one it is a single line.
function M.height(w, fontFile, size, flags, text, wrapWidth)
  local lines = 0
  for _, paragraph in ipairs(paragraphs(text)) do
    lines = lines + (wrapWidth and wrapWidth > 0 and #wrap(w, fontFile, size, flags, paragraph, wrapWidth) or 1)
  end
  return lines * size * M.LINE_HEIGHT
end

return M
