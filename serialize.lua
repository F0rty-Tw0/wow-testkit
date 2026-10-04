-- Deterministic Lua-source dump of plain data: `return <literal>\n`, keys sorted, 2-space indent.
local M = {}

local INDENT = "  "
local MAX_EXACT_INTEGER = 2 ^ 53

local KEYWORDS = {}
for word in ([[and break do else elseif end false for function goto if in local nil not or repeat return then true until while]]):gmatch("%S+") do
  KEYWORDS[word] = true
end

local dumpValue

local function formatNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then
    error("serialize: cannot dump non-finite number " .. tostring(n), 0)
  end
  local mathType = rawget(math, "type")
  if mathType and mathType(n) == "integer" then
    return tostring(n)
  end
  if n == math.floor(n) and math.abs(n) < MAX_EXACT_INTEGER then
    return string.format("%.0f", n)
  end
  return string.format("%.17g", n)
end

local function formatKey(k)
  if type(k) == "string" and k:match("^[%a_][%w_]*$") and not KEYWORDS[k] then
    return k
  end
  return "[" .. dumpValue(k) .. "]"
end

-- Numbers before strings; numbers numerically, strings lexicographically.
local function keyLess(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then
    return ta == "number"
  end
  return a < b
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    local kind = type(k)
    if kind ~= "number" and kind ~= "string" then
      error("serialize: cannot dump a " .. kind .. " key", 0)
    end
    keys[#keys + 1] = k
  end
  table.sort(keys, keyLess)
  return keys
end

-- Length when the keys are exactly 1..n, else nil.
local function arrayLength(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  for i = 1, count do
    if t[i] == nil then
      return nil
    end
  end
  return count
end

local function inlineArray(t, n)
  local items = {}
  for i = 1, n do
    if type(t[i]) == "table" then
      return nil
    end
    items[i] = dumpValue(t[i])
  end
  return "{ " .. table.concat(items, ", ") .. " }"
end

local function dumpTable(t, indent, stack)
  local n = arrayLength(t)
  if n == 0 then
    return "{}"
  end
  local inline = n and inlineArray(t, n)
  if inline then
    return inline
  end
  local inner = indent .. INDENT
  local lines = { "{" }
  for _, k in ipairs(sortedKeys(t)) do
    local prefix = n and "" or (formatKey(k) .. " = ")
    lines[#lines + 1] = inner .. prefix .. dumpValue(t[k], inner, stack) .. ","
  end
  lines[#lines + 1] = indent .. "}"
  return table.concat(lines, "\n")
end

function dumpValue(v, indent, stack)
  local kind = type(v)
  if kind == "string" then
    return string.format("%q", v)
  elseif kind == "number" then
    return formatNumber(v)
  elseif kind == "boolean" or kind == "nil" then
    return tostring(v)
  elseif kind ~= "table" then
    error("serialize: cannot dump a " .. kind, 0)
  end
  if stack[v] then
    error("serialize: cannot dump a cycle", 0)
  end
  stack[v] = true
  local out = dumpTable(v, indent, stack)
  stack[v] = nil
  return out
end

function M.dump(value)
  return "return " .. dumpValue(value, "", {}) .. "\n"
end

return M
