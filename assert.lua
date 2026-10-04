-- Test assertions. Every failure raises an error pointing at the caller's line.
local M = {}

local function fail(msg, prefix)
  error((prefix and (prefix .. ": ") or "") .. msg, 3)
end

local function show(v)
  return type(v) == "string" and string.format("%q", v) or tostring(v)
end

-- Returns the path of the first difference between a and b, or nil when deeply equal.
local function firstDiff(a, b, path)
  if type(a) ~= "table" or type(b) ~= "table" then
    if a == b then
      return nil
    end
    return string.format("%s: expected %s, got %s", path, show(b), show(a))
  end
  for k, v in pairs(a) do
    local diff = firstDiff(v, b[k], path .. "." .. tostring(k))
    if diff then
      return diff
    end
  end
  for k, v in pairs(b) do
    if a[k] == nil then
      return string.format("%s.%s: expected %s, got nil", path, tostring(k), show(v))
    end
  end
  return nil
end

function M.same(actual, expected, msg)
  local diff = firstDiff(actual, expected, "value")
  if diff then
    fail(diff, msg)
  end
end

function M.eq(actual, expected, msg)
  if actual ~= expected then
    fail(string.format("expected %s, got %s", show(expected), show(actual)), msg)
  end
end

function M.truthy(v, msg)
  if not v then
    fail("expected truthy, got " .. show(v), msg)
  end
end

local function hasValue(list, needle)
  for _, v in pairs(list) do
    if v == needle then
      return true
    end
  end
  return false
end

-- String haystack: plain substring search. Table haystack: any value equal to needle.
function M.contains(haystack, needle, msg)
  local found
  if type(haystack) == "table" then
    found = hasValue(haystack, needle)
  else
    found = string.find(tostring(haystack), needle, 1, true) ~= nil
  end
  if not found then
    fail(string.format("expected %s to contain %s", show(haystack), show(needle)), msg)
  end
end

-- fn must raise an error whose message contains needle (when given). Returns the message.
function M.errors(fn, needle)
  local ok, err = pcall(fn)
  if ok then
    fail("expected error" .. (needle and (" containing " .. show(needle)) or "") .. ", but none was raised")
  end
  local message = tostring(err)
  if needle and not string.find(message, needle, 1, true) then
    fail(string.format("expected error containing %s, got %s", show(needle), show(message)))
  end
  return message
end

local function splitLines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

-- Line-by-line text comparison naming the first differing line.
function M.textEq(actual, expected)
  local a, e = splitLines(actual), splitLines(expected)
  for i = 1, math.max(#a, #e) do
    if a[i] ~= e[i] then
      fail(string.format("text differs at line %d\n  expected: %s\n  actual:   %s", i, show(e[i]), show(a[i])))
    end
  end
end

return M
