-- The per-addon environment Addon.load runs each file in: a view of _G that hides host-only names, hands out
-- itself where the host would hand out the real _G, and keeps the metatable addon code gives _G beside it.
local Fenv = require("addon_env_fenv")

local M = {}

local NIL_REQUIRE = "attempt to call a nil value (global 'require')"
-- WoW: Forever has a global require that rejects addon module names.
local FOREVER_REQUIRE = "Invalid import"

local function requireSentinel(flavor)
  local message = flavor == "forever" and FOREVER_REQUIRE or NIL_REQUIRE
  return function()
    error(message, 2)
  end
end

-- Host-only names WoW's client does not have (python and __tk_fs: the lupa hosts' bridges to Python), hidden so addon
-- code reads _G as the client's. Fidelity, not a security boundary: addon code is trusted. An assigned one stays visible.
local HOST_ONLY = { "require", "io", "package", "loadfile", "dofile", "debug", "module", "load", "python", "__tk_fs" }
local HOST_VALUES = {}
for _, name in ipairs(HOST_ONLY) do
  HOST_VALUES[name] = rawget(_G, name)
end
local OS_KEPT = { "time", "date", "clock", "difftime" }

local hostOs, hostLoadstring, hostGetfenv, hostSetfenv = os, loadstring, getfenv, setfenv
local hostRawget, hostRawset, hostNext, hostPairs = rawget, rawset, next, pairs
local hostGetmetatable, hostSetmetatable, hostRawMetatable = getmetatable, setmetatable, debug.getmetatable
local hostType, hostSelect, hostError, hostPcall = type, select, error, pcall
local hostSub, hostGetinfo = string.sub, debug.getinfo

local function keptOs()
  local out = {}
  for _, name in ipairs(OS_KEPT) do
    out[name] = hostOs[name]
  end
  return out
end

-- Lua 5.1's loadstring takes a precompiled (binary) chunk when its first byte is ESC, and runs it unchecked.
local BINARY_REFUSAL = "the chunk is precompiled bytecode, which is never run"

-- The refusal message when source is a binary chunk, else nil.
function M.binaryRefusal(source)
  if hostType(source) == "string" and hostSub(source, 1, 1) == "\27" then
    return BINARY_REFUSAL
  end
end

-- Values the view answers instead of _G's: host-only names map to false (see hidden); functions that would hand
-- out the real _G, or an addon's environment (w.addonEnvs), hand out the view instead: the client has one _G.
local function overridesFor(view, w)
  local overrides = { _G = view, os = keptOs() }
  for _, name in ipairs(HOST_ONLY) do
    overrides[name] = false
  end
  if w.flavor == "forever" then
    overrides.require = requireSentinel(w.flavor)
  end
  overrides.getfenv = function(f)
    if f == nil then
      f = 1
    end
    local env = f == 0 and w.addonThreadEnv or Fenv.call("getfenv", hostGetfenv, f)
    return (env == _G or w.addonEnvs[env]) and view or env
  end
  overrides.loadstring = function(src, chunkName)
    local refusal = M.binaryRefusal(src)
    if refusal then
      return nil, refusal
    end
    local fn, err = hostLoadstring(src, chunkName)
    return fn and (w.taint and w.taint.chunk or hostSetfenv)(fn, w.addonThreadEnv or view), err
  end
  Fenv.addSetfenv(overrides, w)
  return overrides
end

-- True when key is a host-only name still holding its host value.
local function hidden(overrides, key)
  return overrides[key] == false and hostRawget(_G, key) == HOST_VALUES[key]
end

-- What the view answers for key; raw reads _G without its metatable.
local function answer(overrides, key, raw)
  local value = overrides[key]
  if hidden(overrides, key) then
    return nil
  elseif value then
    return value
  elseif raw then
    return hostRawget(_G, key)
  end
  return _G[key]
end

-- rawget/rawset/next/pairs given the view work on _G with the view's answers (hidden names skipped).
local function addRawAccess(overrides, view, w)
  local function viewNext(_, key)
    local k = hostNext(_G, key)
    while k ~= nil and hidden(overrides, k) do
      k = hostNext(_G, k)
    end
    if k ~= nil then
      return k, answer(overrides, k, true)
    end
  end
  overrides.next = function(t, key)
    if t == view then
      return viewNext(t, key)
    end
    return hostNext(t, key)
  end
  overrides.pairs = function(t)
    if t == view then
      return viewNext, t, nil
    end
    return hostPairs(t)
  end
  overrides.rawget = function(t, key)
    if t == view then
      return answer(overrides, key, true)
    end
    return hostRawget(t, key)
  end
  overrides.rawset = function(t, key, value)
    (w.taint and w.taint.write or hostRawset)(t == view and _G or t, key, value)
    return t
  end
end

-- setmetatable/getmetatable given the view act on w.addonGlobalsMt, the metatable addon code gave _G: one per
-- world, shared by every addon view (the client has one _G), never set on the real _G, so kit reads ignore it.
-- Both run Lua 5.1's own argument and __metatable checks (lbaselib.c), raised at the addon's line.
local function addGlobalsMetatable(overrides, view, w)
  local function current(t)
    if t == view then
      return w.addonGlobalsMt
    end
    return hostRawMetatable(t)
  end
  overrides.setmetatable = function(...)
    local t, mt = ...
    local count = hostSelect("#", ...)
    if hostType(t) ~= "table" then
      local got = count < 1 and "no value" or hostType(t)
      hostError("bad argument #1 to 'setmetatable' (table expected, got " .. got .. ")", 2)
    end
    if count < 2 or (mt ~= nil and hostType(mt) ~= "table") then
      hostError("bad argument #2 to 'setmetatable' (nil or table expected)", 2)
    end
    local old = current(t)
    if old and hostRawget(old, "__metatable") ~= nil then
      hostError("cannot change a protected metatable", 2)
    end
    if t ~= view then
      return hostSetmetatable(t, mt)
    end
    w.addonGlobalsMt = mt
    return view
  end
  overrides.getmetatable = function(...)
    if hostSelect("#", ...) < 1 then
      hostError("bad argument #1 to 'getmetatable' (value expected)", 2)
    end
    local t = ...
    if t ~= view then
      return hostGetmetatable(t)
    end
    local mt = w.addonGlobalsMt
    local protected = mt and hostRawget(mt, "__metatable")
    if protected ~= nil then
      return protected
    end
    return mt
  end
end

-- What the addon metatable's handler (__index or __newindex) is, or nil.
local function globalsHandler(w, event)
  return w.addonGlobalsMt and hostRawget(w.addonGlobalsMt, event)
end

-- Calls an addon _G metatable handler; not a tail call, so the handler's error(msg, 2) names this line.
local function invokeHandler(handler, ...)
  local result = handler(...)
  return result
end

-- The "<file>:<line>: " prefix error(msg, 2) in a handler gets: invokeHandler's call line.
local HANDLER_WHERE = hostSelect(
  2,
  pcall(invokeHandler, function()
    error("", 2)
  end)
)

-- Runs a handler for the view's __index or __newindex, which must call this directly (not as a tail call).
-- On a plain table the VM calls the handler from the code that read or wrote the global, so an error the handler
-- raises at level 2 names that line; here the kit's frames sit in between, so that error is re-raised at the
-- addon's line (3 levels up) instead.
local function callHandler(handler, ...)
  local ok, result = hostPcall(invokeHandler, handler, ...)
  if ok then
    return result
  end
  if hostType(result) == "string" and hostSub(result, 1, #HANDLER_WHERE) == HANDLER_WHERE then
    local info = hostGetinfo(3, "Sl")
    local where = info and info.currentline > 0 and (info.short_src .. ":" .. info.currentline .. ": ") or ""
    result = where .. hostSub(result, #HANDLER_WHERE + 1)
  end
  hostError(result, 0)
end

-- The addon's _G: reads see _G through the overrides; writes land in _G (raw, so w:destroy's snapshot removes
-- them). Kit code keeps its own upvalues, so hiding names here never affects it. Like on any table, the addon
-- metatable's __index runs only for absent globals and its __newindex only for new ones.
local function newView(w)
  local view = {}
  local overrides = overridesFor(view, w)
  addRawAccess(overrides, view, w)
  addGlobalsMetatable(overrides, view, w)
  hostSetmetatable(view, {
    __index = function(_, key)
      local value = answer(overrides, key, false)
      local handler = value == nil and globalsHandler(w, "__index")
      if hostType(handler) == "function" then
        value = callHandler(handler, view, key)
      elseif handler then
        value = handler[key]
      end
      return value
    end,
    __newindex = function(_, key, value)
      local handler = globalsHandler(w, "__newindex")
      if handler == nil or (hostRawget(_G, key) ~= nil and not hidden(overrides, key)) then
        (w.taint and w.taint.write or hostRawset)(_G, key, value)
      elseif hostType(handler) == "function" then
        callHandler(handler, view, key, value)
      else
        handler[key] = value
      end
    end,
  })
  return view, overrides
end

-- The world's one view (the client has one _G), made on first use: by the first addon, or by a global-by-name lookup
-- that runs before any addon loads.
local function worldView(w)
  if not w.addonView then
    w.addonView, w.addonOverrides = newView(w)
    w.addonEnvs = w.addonEnvs or {}
    w.addonEnvs[w.addonView] = true
  end
  return w.addonView
end

-- The global `name` as addon code sees it: a host-only name (io, debug, require, ...) is nil and _G is the view, so a
-- name an XML attribute or a widget method resolves never hands addon code the host's own tables. raw reads _G without
-- its metatable (which lazily makes global frames); a global the addon assigned under a host-only name stays visible.
function M.global(w, name, raw)
  worldView(w)
  return answer(w.addonOverrides, name, raw)
end

-- The per-addon environment: the world's view plus the require sentinel, raw in the environment so it shadows any host
-- require. Both are registered in w.addonEnvs, so getfenv in any addon answers the view for them.
function M.newEnv(w)
  local view = worldView(w)
  local env = setmetatable({}, { __index = view, __newindex = view })
  hostRawset(env, "require", requireSentinel(w.flavor))
  w.addonEnvs[env] = true
  return env
end

return M
