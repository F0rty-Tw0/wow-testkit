-- Placeholder text metrics until real font metrics exist: each visible character is half the font size wide,
-- a line is one font size tall. Color codes (|cAARRGGBB, |r) are invisible; UTF-8 characters count once.
local M = {}

M.DEFAULT_FONT_SIZE = 12

local CHAR_WIDTH_RATIO = 0.5
local COLOR_START = "|c%x%x%x%x%x%x%x%x"
local COLOR_END = "|r"
local UTF8_LEAD_BYTE = "[^\128-\191]"

local function visibleCharCount(text)
  local visible = tostring(text or ""):gsub(COLOR_START, ""):gsub(COLOR_END, "")
  local _, count = visible:gsub(UTF8_LEAD_BYTE, "")
  return count
end

function M.stringWidth(text, fontSize)
  return CHAR_WIDTH_RATIO * fontSize * visibleCharCount(text)
end

function M.stringHeight(fontSize)
  return fontSize
end

return M
