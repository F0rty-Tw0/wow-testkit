-- JSON string encoding (json.lua): quotes, escapes control characters, and turns bytes that are not UTF-8 into U+FFFD,
-- because JSON text is UTF-8 and one stray byte (an addon error message holding 0xbb) breaks every reader of the
-- whole snapshot. Pure Lua, 5.1 and 5.4.
local M = {}

local byte, format, sub = string.byte, string.format, string.sub

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
local REPLACEMENT = "\239\191\189" -- U+FFFD

-- Continuation range of a sequence's second byte, by lead byte: the default is 80-BF; these rule out overlong forms
-- (E0, F0), surrogates (ED) and code points past U+10FFFF (F4).
local SECOND = { [0xE0] = { 0xA0, 0xBF }, [0xED] = { 0x80, 0x9F }, [0xF0] = { 0x90, 0xBF }, [0xF4] = { 0x80, 0x8F } }
local DEFAULT_SECOND = { 0x80, 0xBF }

-- The byte length of the sequence a lead byte starts: 2 for C2-DF, 3 for E0-EF, 4 for F0-F4, nil for anything else.
local function lengthOf(lead)
  if lead >= 0xC2 and lead <= 0xDF then
    return 2
  elseif lead >= 0xE0 and lead <= 0xEF then
    return 3
  elseif lead >= 0xF0 and lead <= 0xF4 then
    return 4
  end
  return nil
end

-- The length of the valid UTF-8 sequence of s starting at i (a byte of 0x80 or more), or nil.
local function sequenceAt(s, i)
  local lead = byte(s, i)
  local length = lengthOf(lead)
  if not length then
    return nil
  end
  local range = SECOND[lead] or DEFAULT_SECOND
  for offset = 1, length - 1 do
    local b = byte(s, i + offset)
    local low, high = 0x80, 0xBF
    if offset == 1 then
      low, high = range[1], range[2]
    end
    if not b or b < low or b > high then
      return nil
    end
  end
  return length
end

-- s with each byte that is not part of a valid UTF-8 sequence replaced by U+FFFD.
local function clean(s)
  if not s:find("[\128-\255]") then
    return s
  end
  local parts, i, size = {}, 1, #s
  while i <= size do
    local length = byte(s, i) < 0x80 and 1 or sequenceAt(s, i)
    parts[#parts + 1] = length and sub(s, i, i + length - 1) or REPLACEMENT
    i = i + (length or 1)
  end
  return table.concat(parts)
end

local function escapeChar(char)
  return ESCAPES[char] or format("\\u%04x", byte(char))
end

-- The JSON text of the string s, quotes included.
function M.encode(s)
  return '"' .. clean(s):gsub('[%c"\\]', escapeChar) .. '"'
end

return M
