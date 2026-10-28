-- JSON encoder (pure Lua, 5.1 and 5.4). Keys are sorted so the output is stable. An empty table is an array unless
-- Json.object marked it; a table with only keys 1..n is an array, one with only string keys an object, anything else
-- raises "json: mixed table". Json.null stands for a null inside a list or object (a bare nil would leave a hole).
-- Json.decode reads it back (null becomes Json.null, {} a marked object); bad input raises "json: <reason> at <offset>".
local M = {}

local format, concat, sort, schar, floor = string.format, table.concat, table.sort, string.char, math.floor

local EMPTY_OBJECTS = setmetatable({}, { __mode = "k" })

local encodeString = require("json_string").encode

M.null = {}

-- Marks t as an object, so it encodes as {} when empty. Returns t.
function M.object(t)
  EMPTY_OBJECTS[t] = true
  return t
end

local function encodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then
    error("json: non-finite number", 0)
  end
  return format("%.14g", n)
end

-- "array", "object" or "empty" for t; raises on a mixed table.
local function shapeOf(t)
  local count, strings = 0, 0
  for key in pairs(t) do
    count = count + 1
    if type(key) == "string" then
      strings = strings + 1
    end
  end
  if count == 0 then
    return "empty"
  elseif strings == count then
    return "object"
  elseif strings == 0 and #t == count then
    return "array"
  end
  error("json: mixed table", 0)
end

local function sortedKeys(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  sort(keys)
  return keys
end

local encode

-- parts are already-encoded members; indent is nil (compact) or { step, depth }.
local function wrap(open, close, parts, indent)
  if #parts == 0 then
    return open .. close
  elseif not indent then
    return open .. concat(parts, ",") .. close
  end
  local inner = "\n" .. (" "):rep(indent.step * (indent.depth + 1))
  local outer = "\n" .. (" "):rep(indent.step * indent.depth)
  return open .. inner .. concat(parts, "," .. inner) .. outer .. close
end

local function encodeTable(t, indent)
  local shape = shapeOf(t)
  local child = indent and { step = indent.step, depth = indent.depth + 1 }
  local parts = {}
  if shape == "array" or (shape == "empty" and not EMPTY_OBJECTS[t]) then
    for i = 1, #t do
      parts[i] = encode(t[i], child)
    end
    return wrap("[", "]", parts, indent)
  end
  local colon = indent and ": " or ":"
  for _, key in ipairs(sortedKeys(t)) do
    parts[#parts + 1] = encodeString(key) .. colon .. encode(t[key], child)
  end
  return wrap("{", "}", parts, indent)
end

function encode(value, indent)
  local kind = type(value)
  if kind == "nil" or value == M.null then
    return "null"
  elseif kind == "boolean" then
    return tostring(value)
  elseif kind == "number" then
    return encodeNumber(value)
  elseif kind == "string" then
    return encodeString(value)
  elseif kind == "table" then
    return encodeTable(value, indent)
  end
  error("json: cannot encode a " .. kind, 0)
end

-- indent: spaces per level; nil encodes compactly.
function M.encode(value, indent)
  return encode(value, indent and { step = indent, depth = 0 })
end

local MAX_DEPTH = 1000
local LITERALS = { t = { "true", true }, f = { "false", false }, n = { "null", M.null } }
local SIMPLE_ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function fail(pos, reason)
  error(format("json: %s at %d", reason, pos), 0)
end

local function skipSpace(text, pos)
  return text:match("^[ \t\r\n]*()", pos)
end

local parseValue

local function parseLiteral(text, pos, word, value)
  for i = 1, #word do
    if text:byte(pos + i - 1) ~= word:byte(i) then
      fail(pos + i - 1, "invalid literal")
    end
  end
  return value, pos + #word
end

-- The digits at pos (at least one) end at the returned position.
local function parseDigits(text, pos)
  local after = text:match("^%d+()", pos)
  return after or fail(pos, "invalid number")
end

local function parseNumber(text, pos)
  local after = pos
  if text:sub(after, after) == "-" then
    after = after + 1
  end
  after = text:match("^0()", after) or parseDigits(text, after)
  if text:sub(after, after) == "." then
    after = parseDigits(text, after + 1)
  end
  if text:find("^[eE]", after) then
    after = parseDigits(text, text:match("^[eE][+-]?()", after))
  end
  return tonumber(text:sub(pos, after - 1)), after
end

local function utf8Char(code)
  if code < 0x80 then
    return schar(code)
  elseif code < 0x800 then
    return schar(0xC0 + floor(code / 0x40), 0x80 + code % 0x40)
  elseif code < 0x10000 then
    return schar(0xE0 + floor(code / 0x1000), 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
  end
  return schar(0xF0 + floor(code / 0x40000), 0x80 + floor(code / 0x1000) % 0x40, 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

-- The four hex digits after "\u" at pos (the backslash); returns the code and the position after them.
local function parseHex4(text, pos)
  for i = pos + 2, pos + 5 do
    if not text:find("^%x", i) then
      fail(i, "invalid \\u escape")
    end
  end
  return tonumber(text:sub(pos + 2, pos + 5), 16), pos + 6
end

-- The \uXXXX escape at pos; a high surrogate takes the \uXXXX low surrogate after it.
local function parseUnicode(text, pos)
  local code, after = parseHex4(text, pos)
  if code >= 0xDC00 and code <= 0xDFFF then
    fail(pos, "lone low surrogate")
  elseif code >= 0xD800 and code <= 0xDBFF then
    if text:sub(after, after + 1) ~= "\\u" then
      fail(after, "lone high surrogate")
    end
    local low
    low, after = parseHex4(text, after)
    if low < 0xDC00 or low > 0xDFFF then
      fail(after - 6, "lone high surrogate")
    end
    code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
  end
  return utf8Char(code), after
end

-- Bytes a string body may not hold raw (controls, quote, backslash): the complement of the allowed ones, ] first.
local STRING_STOP = "[^]\32-\33\35-\91\94-\255]"

local function parseString(text, pos)
  local parts, from = {}, pos + 1
  while true do
    local stop = text:find(STRING_STOP, from)
    if not stop then
      fail(#text + 1, "unterminated string")
    end
    parts[#parts + 1] = text:sub(from, stop - 1)
    local byte = text:sub(stop, stop)
    if byte == '"' then
      return concat(parts), stop + 1
    elseif byte ~= "\\" then
      fail(stop, "control character in string")
    end
    local escape = text:sub(stop + 1, stop + 1)
    if escape == "u" then
      parts[#parts + 1], from = parseUnicode(text, stop)
    elseif SIMPLE_ESCAPES[escape] then
      parts[#parts + 1], from = SIMPLE_ESCAPES[escape], stop + 2
    else
      fail(stop + 1, "invalid escape")
    end
  end
end

local function parseArray(text, pos, depth)
  local list, at = {}, skipSpace(text, pos + 1)
  if text:sub(at, at) == "]" then
    return list, at + 1
  end
  while true do
    list[#list + 1], at = parseValue(text, at, depth)
    at = skipSpace(text, at)
    local byte = text:sub(at, at)
    if byte == "]" then
      return list, at + 1
    elseif byte ~= "," then
      fail(at, "expected , or ]")
    end
    at = skipSpace(text, at + 1)
  end
end

local function parseObject(text, pos, depth)
  local object, at = {}, skipSpace(text, pos + 1)
  if text:sub(at, at) == "}" then
    return M.object(object), at + 1
  end
  while true do
    if text:sub(at, at) ~= '"' then
      fail(at, "expected a string key")
    end
    local key
    key, at = parseString(text, at)
    at = skipSpace(text, at)
    if text:sub(at, at) ~= ":" then
      fail(at, "expected :")
    end
    object[key], at = parseValue(text, skipSpace(text, at + 1), depth)
    at = skipSpace(text, at)
    local byte = text:sub(at, at)
    if byte == "}" then
      return object, at + 1
    elseif byte ~= "," then
      fail(at, "expected , or }")
    end
    at = skipSpace(text, at + 1)
  end
end

function parseValue(text, pos, depth)
  local byte = text:sub(pos, pos)
  if byte == "{" or byte == "[" then
    if depth >= MAX_DEPTH then
      fail(pos, "nested too deep")
    end
    return (byte == "{" and parseObject or parseArray)(text, pos, depth + 1)
  elseif byte == '"' then
    return parseString(text, pos)
  elseif LITERALS[byte] then
    return parseLiteral(text, pos, LITERALS[byte][1], LITERALS[byte][2])
  elseif byte == "-" or byte:find("^%d") then
    return parseNumber(text, pos)
  end
  fail(pos, pos > #text and "unexpected end of input" or "unexpected character")
end

-- Reads one JSON document; raises "json: <reason> at <offset>" (1-based byte) on bad input.
function M.decode(text)
  local value, after = parseValue(text, skipSpace(text, 1), 0)
  after = skipSpace(text, after)
  if after <= #text then
    fail(after, "unexpected trailing character")
  end
  return value
end

return M
