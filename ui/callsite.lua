-- The error() level of the first caller outside the kit's widget layer, FrameXML fakes, world*.lua and luaext.lua.
-- Widget methods reach their bodies through a different number of tail calls per method (bind, BehaviourInput's
-- SetScript wrapper), and Lua 5.1 counts each lost tail call as a level, so a fixed level can land on a frame with no
-- position.
-- luaext.lua is skipped whole, not only hooksecurefunc's wrapper: its other callers of addon-supplied functions
-- (the C_Timer closures, securecall) stand in for C functions, which have no Lua line in the client. A misuse error
-- through them, such as C_Timer.After(0, ToggleDropDownMenu), walks past them to a C frame and carries no position,
-- not a luaext.lua line that would mean nothing to the addon author (row S22, assumed).
local M = {}

local fs = require("fs")

local getinfo = debug.getinfo
local KIT_ROOT = getinfo(1, "S").source:match("^@(.*)ui[/\\]callsite%.lua$") or ""

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
  local named = rest:match("^ui[/\\]") ~= nil
    or rest:match("^framexml[/\\]") ~= nil
    or rest:match("^world[%w_]*%.lua$") ~= nil
    or rest == "luaext.lua" -- whole file: its callers of addon functions stand in for C functions (header)
  return named and fs.exists(KIT_ROOT .. rest)
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

-- The addon a kit call is credited to: nil outside addon context; else the <Name> of the nearest addon chunk
-- (@addon:<Name>/<file>) on the stack, else the addon whose files are loading (w.dev.loading).
function M.addon(w)
  if not w:callerIsAddon() then
    return nil
  end
  local level = 2
  while true do
    local info = getinfo(level, "S")
    if not info then
      return w.dev.loading
    end
    local name = info.source:match("^@addon:([^/]+)/")
    if name then
      return name
    end
    level = level + 1
  end
end

-- Counts key once under w.dev[field][addon] for the addon M.addon credits; nothing outside addon context.
function M.credit(w, field, key)
  local addon = M.addon(w)
  if not addon then
    return
  end
  local byAddon = w.dev[field]
  local counts = byAddon[addon] or {}
  byAddon[addon] = counts
  counts[key] = (counts[key] or 0) + 1
end

return M
