-- Text measurement. Fallback estimate until glyph tables exist (Measure.useGlyphs): each visible character is
-- AVERAGE_ADVANCE * size wide, a line is LINE_HEIGHT * size tall. UI escapes (visibleWidth) are invisible, a
-- texture is as wide as it is drawn, "||" is one pipe and a UTF-8 character counts once. Both ratios are assumed
-- (row LY10, ruling R2).
local M = {}

M.AVERAGE_ADVANCE = 0.5
M.LINE_HEIGHT = 1.15
M.DEFAULT_FONT_SIZE = 12

local UTF8_LEAD_BYTE = "[^\128-\191]"

-- Stores per-font glyph tables: tables[fontFile].width(size, flags, text) then measures a line of that font.
function M.useGlyphs(w, tables)
  w.measure = { glyphs = tables }
end

local function charCount(text)
  local _, count = text:gsub(UTF8_LEAD_BYTE, "")
  return count
end

-- source: wiki UI_escape_sequences, |T: `|Tpath:height[:width[:offsetX:offsetY...]]|t`, "TextHeight is based on size of
-- the font used". Height 0 with no width is a square of TextHeight; a positive height with no width a square of that
-- height; a positive height with width 0 has width TextHeight; height 0 with a positive width has width * TextHeight;
-- both positive set the width. TextHeight is the font size. That the texture advances the line by its width is
-- assumed (the page does not say).
local function textureWidth(params, size)
  local height = tonumber(params:match("^[^:]*:([^:]*)")) or 0
  local width = tonumber(params:match("^[^:]*:[^:]*:([^:]*)"))
  if width == nil then
    return height > 0 and height or size
  elseif width == 0 then
    return size
  end
  return height > 0 and width or width * size
end

-- source: wiki UI_escape_sequences: `|cAARRGGBB` ... `|r` color, `||` "Escapes the "|" character", `|T...|t` texture; wiki
-- Hyperlinks: `|cffxxxxxx|Htype:payload|h[text]|h|r`, where only `[text]` is shown, so `|H...|h` and the closing `|h`
-- take no room. Width of the visible part of line: characters at AVERAGE_ADVANCE * size, textures at their own width.
-- An unknown `|x` counts as the pipe and the letter.
local function visibleWidth(line, size)
  local chars, textures, pos = 0, 0, 1
  while true do
    local bar = line:find("|", pos, true)
    chars = chars + charCount(line:sub(pos, (bar or #line + 1) - 1))
    if not bar then
      return chars * M.AVERAGE_ADVANCE * size + textures
    end
    local nextPos = line:match("^|c%x%x%x%x%x%x%x%x()", bar) or line:match("^|[rh]()", bar) or line:match("^|H[^|]*|h()", bar)
    local params, textureEnd = line:match("^|T([^|]*)|t()", bar)
    if params then
      textures, nextPos = textures + textureWidth(params, size), textureEnd
    elseif not nextPos then
      chars = chars + 1 -- "||" is one pipe; any other "|" stands for itself
      nextPos = line:sub(bar + 1, bar + 1) == "|" and bar + 2 or bar + 1
    end
    pos = nextPos
  end
end

local function lineWidth(w, fontFile, size, flags, line)
  local glyphs = w.measure and fontFile and w.measure.glyphs[fontFile]
  if glyphs then
    return glyphs.width(size, flags, line)
  end
  return visibleWidth(line, size)
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
