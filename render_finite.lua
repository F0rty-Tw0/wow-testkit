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

-- A copy of value with every non-finite number and every list hole replaced by Json.null. Empty tables are returned
-- as they are, so a Json.object mark survives.
function M.scrub(value)
  if type(value) == "number" then
    return finite(value) and value or Json.null
  elseif type(value) ~= "table" or next(value) == nil then
    return value
  end
  local copy, size, named = {}, 0, false
  for key, member in pairs(value) do
    if type(key) == "number" then
      size = math.max(size, key)
    else
      named = true
    end
    copy[key] = M.scrub(member)
  end
  for i = 1, named and 0 or size do
    copy[i] = copy[i] == nil and Json.null or copy[i]
  end
  return copy
end

return M
