-- The getfenv/setfenv helpers of the per-addon environment (addon_env.lua), kept apart for its 300-line cap.
local M = {}

local hostGetfenv, hostSetfenv, hostType, hostTonumber = getfenv, setfenv, type, tonumber
local hostError, hostPcall, hostSelect = error, pcall, select
local hostGsub, hostGetinfo = string.gsub, debug.getinfo

-- Runs hostFn, the host getfenv or setfenv, for the override name that addon code called with (f, ...): under pcall
-- here, a level counted from the addon's function is three deeper. Errors are re-raised at the addon's line under
-- name, as Lua 5.1's C function raises them. An override called in tail position (`return getfenv()`) has replaced
-- the addon's function, so level 1 reaches nothing: that raises saying so. As a coroutine body the override has no
-- caller at all, and level 1 is an invalid level.
local function callHostFenv(name, hostFn, ...)
  local f = ...
  local level = hostType(f) ~= "function" and hostTonumber(f)
  local caller = hostGetinfo(3, "S")
  if level == 1 and caller and caller.what == "tail" then
    hostError("'" .. name .. "' cannot reach the calling function: a tail call (return " .. name .. "(...)) replaced it", 0)
  end
  local ok, result = hostPcall(hostFn, level and level > 0 and level + 3 or f, hostSelect(2, ...))
  if not ok then
    result = hostGsub(result, "^bad argument (#%d) to '%?'", "bad argument %1 to '" .. name .. "'")
    result = level and hostGsub(result, "at level %d+$", "at level " .. level) or result
    hostError(result, 3)
  end
  return result
end

-- setfenv(0, t) sets the world's addon thread environment (w.addonThreadEnv, read by getfenv(0) and loadstring),
-- never the host thread's, so kit code loaded meanwhile keeps the real _G. A function whose environment is the
-- host's _G is kit (or host) code, the client's C functions: refused with Lua 5.1's message for those.
local function addSetfenv(overrides, w)
  overrides.setfenv = function(...)
    local f, env = ...
    local level = hostType(f) ~= "function" and hostTonumber(f)
    if level == 0 and hostType(env) == "table" then
      w.addonThreadEnv = env
      return
    end
    local info = level and level > 0 and hostGetinfo(level + 1, "f")
    local target = info and info.func or f
    if hostType(env) == "table" and hostType(target) == "function" and hostGetfenv(target) == _G then
      hostError("'setfenv' cannot change environment of given object", 2)
    end
    local fn = callHostFenv("setfenv", hostSetfenv, ...)
    return fn
  end
end

M.call = callHostFenv
M.addSetfenv = addSetfenv

return M
