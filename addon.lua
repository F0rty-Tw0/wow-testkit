-- Loads an addon into a world the way the client does: picks and parses the TOC for the world's flavor, then runs
-- each Lua file as chunk(name, ns) in one per-addon environment. A file that fails to compile or errors at load goes
-- to the error handler (by default w.errors) and loading continues with the next file.
local M = {}

local Flavors = require("tools.flavors")
local Toc = require("toc")
local fs = require("fs")

local NOT_DECLARED = "not-declared"
local NIL_REQUIRE = "attempt to call a nil value (global 'require')"
-- WoW: Forever has a global require that rejects addon module names.
local FOREVER_REQUIRE = "Invalid import"

local function requireSentinel(flavor)
  local message = flavor == "forever" and FOREVER_REQUIRE or NIL_REQUIRE
  return function()
    error(message, 2)
  end
end

-- Host-only names WoW's client does not have; addon code never sees their host values, whatever path it reads _G
-- through. A global the addon itself assigns under one of these names stays visible.
local HOST_ONLY = { "require", "io", "package", "loadfile", "dofile", "debug", "module", "load" }
local HOST_VALUES = {}
for _, name in ipairs(HOST_ONLY) do
  HOST_VALUES[name] = rawget(_G, name)
end
local OS_KEPT = { "time", "date", "clock", "difftime" }

local hostOs, hostLoadstring, hostGetfenv, hostSetfenv = os, loadstring, getfenv, setfenv
local hostRawget, hostRawset, hostNext, hostPairs = rawget, rawset, next, pairs
local hostGetmetatable, hostSetmetatable, hostRawMetatable = getmetatable, setmetatable, debug.getmetatable
local hostType, hostSelect, hostError = type, select, error

local function keptOs()
  local out = {}
  for _, name in ipairs(OS_KEPT) do
    out[name] = hostOs[name]
  end
  return out
end

-- Values the view answers instead of _G's: host-only names map to false (see hidden); functions that would hand
-- out the real _G hand out the view instead.
local function overridesFor(view, flavor)
  local overrides = { _G = view, os = keptOs() }
  for _, name in ipairs(HOST_ONLY) do
    overrides[name] = false
  end
  if flavor == "forever" then
    overrides.require = requireSentinel(flavor)
  end
  overrides.getfenv = function(f)
    if f == nil then
      f = 1
    end
    local env = hostGetfenv(type(f) == "number" and f > 0 and f + 1 or f)
    return env == _G and view or env
  end
  overrides.loadstring = function(src, chunkName)
    local fn, err = hostLoadstring(src, chunkName)
    return fn and hostSetfenv(fn, view), err
  end
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
local function addRawAccess(overrides, view)
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
    hostRawset(t == view and _G or t, key, value)
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

-- The addon _G metatable's __index answer for an absent global.
local function missingGlobal(w, view, key)
  local handler = globalsHandler(w, "__index")
  if type(handler) == "function" then
    return handler(view, key)
  elseif handler ~= nil then
    return handler[key]
  end
  return nil
end

-- The addon's _G: reads see _G through the overrides; writes land in _G (raw, so w:destroy's snapshot removes
-- them). Kit code keeps its own upvalues, so hiding names here never affects it. Like on any table, the addon
-- metatable's __index runs only for absent globals and its __newindex only for new ones.
local function newView(w)
  local view = {}
  local overrides = overridesFor(view, w.flavor)
  addRawAccess(overrides, view)
  addGlobalsMetatable(overrides, view, w)
  return hostSetmetatable(view, {
    __index = function(_, key)
      local value = answer(overrides, key, false)
      if value == nil then
        return missingGlobal(w, view, key)
      end
      return value
    end,
    __newindex = function(_, key, value)
      local handler = globalsHandler(w, "__newindex")
      if handler == nil or (hostRawget(_G, key) ~= nil and not hidden(overrides, key)) then
        hostRawset(_G, key, value)
      elseif type(handler) == "function" then
        handler(view, key, value)
      else
        handler[key] = value
      end
    end,
  })
end

-- The per-addon environment: the view plus the require sentinel, raw in the environment so it shadows any host
-- require.
local function newEnv(w)
  local view = newView(w)
  local env = setmetatable({}, { __index = view, __newindex = view })
  hostRawset(env, "require", requireSentinel(w.flavor))
  return env
end

-- Reads a TOC- or XML-listed file. A missing one is a packaging bug in the addon, so it is an error.
local function readListed(w, ctx, relative)
  local text = fs.readFile(ctx.root .. "/" .. relative)
  if not text then
    w:reportError("TOC lists missing file: addon:" .. ctx.name .. "/" .. relative)
  end
  return text
end

local function runFile(w, ctx, relative)
  local source = readListed(w, ctx, relative)
  if not source then
    ctx.report[#ctx.report + 1] = relative .. ": cannot read file; skipped"
    return
  end
  local chunkName = "addon:" .. ctx.name .. "/" .. relative
  w:registerChunk(chunkName)
  local chunk, loadErr = loadstring(source, "@" .. chunkName)
  if not chunk then
    w:reportError(loadErr)
    return
  end
  setfenv(chunk, ctx.env)
  w:callAsAddon(chunk, ctx.name, ctx.ns)
end

local function versionNote(declared, flavor)
  local row = Flavors.get(flavor)
  return string.format("TOC interface is %s for %s (client %d); loaded anyway", declared, flavor, row.tocVersion)
end

-- True when root holds a TOC for name on any flavor (a flavor-suffixed one or the bare <name>.toc).
local function hasAnyToc(root, name)
  for _, flavor in ipairs(Flavors.list) do
    if fs.exists(Toc.select(root, name, flavor)) then
      return true
    end
  end
  return false
end

-- opts: { name, root }. Returns ns, info = { status = "loaded"|"skipped", reason, toc, declared, report,
-- savedVariables, savedVariablesPerCharacter }. No TOC for this flavor but one for another: skipped, with only
-- status, reason and report. No TOC for the name at all: an error.
function M.load(w, opts)
  local name, root = opts.name, opts.root
  local tocPath = Toc.select(root, name, w.flavor)
  if not fs.exists(tocPath) and hasAnyToc(root, name) then
    return {}, { status = "skipped", reason = "no TOC for this flavor", report = {} }
  end
  local parsed = Toc.parse(assert(fs.readFile(tocPath), "cannot read TOC " .. tocPath))
  local info = {
    toc = tocPath,
    declared = Toc.declared(parsed.meta, w.flavor),
    report = {},
    savedVariables = parsed.savedVariables,
    savedVariablesPerCharacter = parsed.savedVariablesPerCharacter,
  }
  local ns = {}
  if info.declared == NOT_DECLARED then
    info.status, info.reason = "skipped", "not declared"
    return ns, info
  end
  info.status = "loaded"
  local ctx = { name = name, root = root, ns = ns, env = newEnv(w) }
  local files, report = Toc.filesFor(parsed, w.flavor, function(path)
    return readListed(w, ctx, path)
  end)
  info.report, ctx.report = report, report
  if info.declared ~= "load" then
    table.insert(report, 1, versionNote(info.declared, w.flavor))
  end
  for _, relative in ipairs(files) do
    runFile(w, ctx, relative)
  end
  return ns, info
end

-- Sets each SavedVariables / SavedVariablesPerCharacter global from saved[name] (nil when absent).
function M.applySaved(w, info, saved)
  saved = saved or {}
  for _, names in ipairs({ info.savedVariables, info.savedVariablesPerCharacter }) do
    for _, name in ipairs(names) do
      w:setGlobal(name, saved[name])
    end
  end
end

return M
