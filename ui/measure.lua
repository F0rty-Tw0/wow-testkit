-- Text measurement. Fallback estimate until glyph tables exist (Measure.useGlyphs): each visible character is
-- AVERAGE_ADVANCE * size wide, a line is LINE_HEIGHT * size tall. UI escapes (visibleWidth) are invisible, a
-- texture or atlas is as wide as it is drawn, "||" is one pipe and a UTF-8 character counts once. Both ratios are assumed
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

local function isDigit(text, at)
  local byte = text:byte(at)

  return byte >= 48 and byte <= 57
end

-- The last run of digits in text as a number, or nil. A backwards scan: `(%d+)%D*$` backtracks over every start of a
-- long digit run, quadratic in its length (viewer_text.js lastNumber scans the same way).
local function lastNumber(text)
  local stop = #text
  while stop > 0 and not isDigit(text, stop) do
    stop = stop - 1
  end
  local start = stop
  while start > 0 and isDigit(text, start) do
    start = start - 1
  end

  return tonumber(text:sub(start + 1, stop))
end

-- source: row V14, wiki UI_escape_sequences: `number |4singular:plural;` "assigns the singular or plural form depending
-- on the number" ("1 |4car:cars;" is "1 car", "2 |4car:cars;" "2 cars"). forms is "singular:plural"; before is the text
-- shown ahead of the escape on its line. Assumed: the number is the last one in before, singular only when it is 1, the
-- plural with no number; the ruRU third form is not chosen.
function M.pluralForm(forms, before)
  local singular, plural = forms:match("^([^:]*):?([^:]*)")
  local number = lastNumber(before)

  return number == 1 and singular or plural
end

-- Estimated width of a run of visible text: each character at AVERAGE_ADVANCE * size.
local function estimateRun(text, size)
  return charCount(text) * M.AVERAGE_ADVANCE * size
end

-- source: wiki UI_escape_sequences: `|cAARRGGBB` ... `|r` color, `|cncolorname:text|r` named color (the start ends at the
-- colon, `|r` closes it), `||` "Escapes the "|" character", `|T...|t` texture, `|A:atlas:height:width[:offsetX...]|a`
-- atlas markup (the page gives no sizing rule for it, so its height and width fields are read like |T's: assumed);
-- wiki Hyperlinks: `|cffxxxxxx|Htype:payload|h[text]|h|r`, where only `[text]` is shown, so `|H...|h` and the closing `|h`
-- take no room. Width of the visible part of line: textures at their own width, the text between them (colour and
-- link escapes removed, "||" folded to one pipe, `|4singular:plural;` replaced by M.pluralForm) through
-- runWidth(text, size). An unknown `|x` counts as the pipe and the letter.
local function visibleWidth(line, size, runWidth)
  local run, shown, width, pos = {}, {}, 0, 1
  while true do
    local bar = line:find("|", pos, true)
    local piece = line:sub(pos, (bar or #line + 1) - 1)
    run[#run + 1], shown[#shown + 1] = piece, piece
    if not bar then
      return width + runWidth(table.concat(run), size)
    end
    local nextPos = line:match("^|c%x%x%x%x%x%x%x%x()", bar) or line:match("^|cn[%w_]+:()", bar)
    nextPos = nextPos or line:match("^|[rh]()", bar) or line:match("^|H[^|]*|h()", bar)
    local params, textureEnd = line:match("^|T([^|]*)|t()", bar)
    if not params then
      params, textureEnd = line:match("^|A:([^|]*)|a()", bar)
    end
    local forms, pluralEnd = line:match("^|4([^;|]*);()", bar)
    if params then
      width = width + runWidth(table.concat(run), size) + textureWidth(params, size)
      run, nextPos = {}, textureEnd
    elseif forms then
      local form = M.pluralForm(forms, table.concat(shown))
      run[#run + 1], shown[#shown + 1], nextPos = form, form, pluralEnd
    elseif not nextPos then
      run[#run + 1] = "|" -- "||" is one pipe; any other "|" stands for itself
      nextPos = line:sub(bar + 1, bar + 1) == "|" and bar + 2 or bar + 1
    end
    pos = nextPos
  end
end

-- Width of one line with the text between its textures measured by runWidth(text, size): the glyph tables' hook.
M.scanLine = visibleWidth

local function lineWidth(w, fontFile, size, flags, line)
  local glyphs = w.measure and fontFile and w.measure.glyphs[fontFile]
  if glyphs then
    return glyphs.width(size, flags, line)
  end
  return visibleWidth(line, size, estimateRun)
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

-- The lines text breaks into: each paragraph is one line, or with wrapWidth > 0 it wraps (see wrap).
function M.lines(w, fontFile, size, flags, text, wrapWidth)
  local lines = {}
  for _, paragraph in ipairs(paragraphs(text)) do
    if wrapWidth and wrapWidth > 0 then
      for _, line in ipairs(wrap(w, fontFile, size, flags, paragraph, wrapWidth)) do
        lines[#lines + 1] = line
      end
    else
      lines[#lines + 1] = paragraph
    end
  end
  return lines
end

-- Number of lines: with wrapWidth > 0 each paragraph wraps, without one it is a single line.
function M.lineCount(w, fontFile, size, flags, text, wrapWidth)
  return #M.lines(w, fontFile, size, flags, text, wrapWidth)
end

-- Width of the widest of the first maxLines lines (all of them when maxLines is nil or 0).
local function widest(w, fontFile, size, flags, lines, maxLines)
  local last = maxLines and maxLines > 0 and math.min(maxLines, #lines) or #lines
  local widthOfWidest = 0
  for i = 1, last do
    widthOfWidest = math.max(widthOfWidest, lineWidth(w, fontFile, size, flags, lines[i]))
  end
  return widthOfWidest
end

-- Width of the widest paragraph; wrapping does not change it. maxLines keeps only the first paragraphs.
function M.width(w, fontFile, size, flags, text, maxLines)
  return widest(w, fontFile, size, flags, M.lines(w, fontFile, size, flags, text, nil), maxLines)
end

-- Width of the widest wrapped line among the first maxLines.
function M.wrappedWidth(w, fontFile, size, flags, text, wrapWidth, maxLines)
  return widest(w, fontFile, size, flags, M.lines(w, fontFile, size, flags, text, wrapWidth), maxLines)
end

-- Lines * size * LINE_HEIGHT.
function M.height(w, fontFile, size, flags, text, wrapWidth)
  return M.lineCount(w, fontFile, size, flags, text, wrapWidth) * size * M.LINE_HEIGHT
end

return M
