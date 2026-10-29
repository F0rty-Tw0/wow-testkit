-- Keeps the render snapshot encodable: addon code can store NaN, infinity or a nil argument anywhere a number goes.
-- A rect with such a number cannot be placed (render.lua lists it as unplaced); any other bad number, and any hole in
-- a list, becomes Json.null.
local M = {}

local Json = require("json")

local HUGE = math.huge

local function finite(n)
  return n == n and n ~= HUGE and n ~= -HUGE
end

-- True when every side of rect is a finite number.
function M.rect(rect)
  return finite(rect.x) and finite(rect.y) and finite(rect.width) and finite(rect.height)
end

-- Most holes a list may have and still be filled: more means a table that only happens to hold a number key.
local MAX_HOLES = 16

-- Limits on one scrub call, which covers the whole snapshot. A table nested deeper than MAX_DEPTH (a chain of 90000
-- overflows the stack here and in Json.encode) and any table copied again once MAX_REPEATS repeat copies are spent
-- (v = { v, v } twenty-two deep is a handful of tables but 2^22 copies) become Json.null. Distinct tables are not
-- limited, so a large snapshot is copied whole.
local MAX_DEPTH = 100
local MAX_REPEATS = 100000

-- True when value must not be copied again: it is on the path being copied (it contains itself), or it was copied
-- before and the repeat budget is spent. `walk` is { path = tables being copied now, seen = tables copied at all,
-- repeats = repeat copies still allowed }.
local function refused(value, walk, depth)
  if depth > MAX_DEPTH or walk.path[value] then
    return true
  elseif walk.seen[value] then
    walk.repeats = walk.repeats - 1
    return walk.repeats < 0
  end
  return false
end

-- A copy of value with every non-finite number and every list hole replaced by Json.null. A table Json cannot write
-- (positions far apart, such as an infinite key, or mixed with names or odd keys) or that scrub refuses (see above)
-- becomes Json.null. Empty tables are returned as they are, so a Json.object mark survives.
local function scrubIn(value, walk, depth)
  if type(value) == "number" then
    return finite(value) and value or Json.null
  elseif type(value) ~= "table" or next(value) == nil then
    return value
  elseif refused(value, walk, depth) then
    return Json.null
  end
  walk.path[value], walk.seen[value] = true, true
  local copy, size, count, named, odd = {}, 0, 0, false, false
  -- Keys and scalar members are checked inline: a call per member made this loop ~30% of a large snapshot.
  for key, member in pairs(value) do
    local keyKind = type(key)
    if keyKind == "number" and key >= 1 and key % 1 == 0 then
      if key > size then
        size = key
      end
      count = count + 1
    elseif keyKind == "string" then
      named = true
    else
      odd = true
    end
    local kind = type(member)
    if kind == "table" then
      copy[key] = scrubIn(member, walk, depth + 1)
    elseif kind == "number" and (member ~= member or member == HUGE or member == -HUGE) then
      copy[key] = Json.null
    else
      copy[key] = member
    end
  end
  walk.path[value] = nil
  if odd or (named and count > 0) or size > count + MAX_HOLES then
    return Json.null
  end
  if count < size then
    for i = 1, size do
      copy[i] = copy[i] == nil and Json.null or copy[i]
    end
  end
  return copy
end

function M.scrub(value)
  return scrubIn(value, { path = {}, seen = {}, repeats = MAX_REPEATS }, 1)
end

return M
