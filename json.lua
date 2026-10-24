-- JSON encoder (pure Lua, 5.1 and 5.4). Keys are sorted so the output is stable. An empty table is an array unless
-- Json.object marked it; a table with only keys 1..n is an array, one with only string keys an object, anything else
-- raises "json: mixed table".
local M = {}

local format, concat, sort = string.format, table.concat, table.sort

local EMPTY_OBJECTS = setmetatable({}, { __mode = "k" })

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }

-- Marks t as an object, so it encodes as {} when empty. Returns t.
function M.object(t)
  EMPTY_OBJECTS[t] = true
  return t
end

local function escapeChar(char)
  return ESCAPES[char] or format("\\u%04x", char:byte())
end

local function encodeString(s)
  return '"' .. s:gsub('[%c"\\]', escapeChar) .. '"'
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
  if kind == "nil" then
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

return M
