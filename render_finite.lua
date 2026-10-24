-- Keeps the render snapshot encodable: addon code can store NaN, infinity or a nil argument anywhere a number goes.
-- A rect with such a number cannot be placed (render.lua lists it as unplaced); any other bad number, and any hole in
-- a list, becomes Json.null.
local M = {}

local Json = require("json")

local function finite(n)
  return n == n and n ~= math.huge and n ~= -math.huge
end

-- True when every side of rect is a finite number.
function M.rect(rect)
  return finite(rect.x) and finite(rect.y) and finite(rect.width) and finite(rect.height)
end

-- Most holes a list may have and still be filled: more means a table that only happens to hold a number key.
local MAX_HOLES = 16

local function isPosition(key)
  return type(key) == "number" and key >= 1 and key % 1 == 0
end

-- A copy of value with every non-finite number and every list hole replaced by Json.null. A table Json cannot write
-- (positions far apart, such as an infinite key, or mixed with names or odd keys) becomes Json.null. Empty tables are
-- returned as they are, so a Json.object mark survives.
function M.scrub(value)
  if type(value) == "number" then
    return finite(value) and value or Json.null
  elseif type(value) ~= "table" or next(value) == nil then
    return value
  end
  local copy, size, count, named, odd = {}, 0, 0, false, false
  for key, member in pairs(value) do
    if isPosition(key) then
      size, count = math.max(size, key), count + 1
    elseif type(key) == "string" then
      named = true
    else
      odd = true
    end
    copy[key] = M.scrub(member)
  end
  if odd or (named and count > 0) or size > count + MAX_HOLES then
    return Json.null
  end
  for i = 1, size do
    copy[i] = copy[i] == nil and Json.null or copy[i]
  end
  return copy
end

return M
