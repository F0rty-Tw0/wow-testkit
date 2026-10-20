-- The error() level of the first caller outside the kit's widget layer. Widget methods reach their bodies through a
-- different number of tail calls per method (bind, BehaviourInput's SetScript wrapper), and Lua 5.1 counts each
-- lost tail call as a level, so a fixed level can land on a frame with no position.
local M = {}

local getinfo = debug.getinfo
local KIT_ROOT = getinfo(1, "S").source:match("^@(.*)ui[/\\]callsite%.lua$") or ""

local function exists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
  end
  return file ~= nil
end

-- A name match alone is not enough: with a relative KIT_ROOT ("" under a bare "?.lua" package.path) a consumer's
-- "@ui/x.lua" would match, so the file must also exist in the kit.
local function isKit(info)
  if info.what == "tail" then
    return true
  end
  local source = info.source
  if source:sub(1, #KIT_ROOT + 1) ~= "@" .. KIT_ROOT then
    return false
  end
  local rest = source:sub(#KIT_ROOT + 2)
  local named = rest:match("^ui[/\\]") ~= nil or rest:match("^world[%w_]*%.lua$") ~= nil
  return named and exists(KIT_ROOT .. rest)
end

-- The level to pass to error() from the function that calls M.level().
function M.level()
  local level = 3
  while true do
    local info = getinfo(level, "S")
    if not info then
      return 2
    end
    if not isKit(info) then
      return level - 1
    end
    level = level + 1
  end
end

return M
