-- The secure-execution APIs, answered from the taint state (taint.lua): issecure, issecurevariable, securecall,
-- securecallfunction, securecallmethod, secureexecuterange and forceinsecure. Installed by Taint.install (gate "none",
-- counted and validated through w:install where the API lists them).
local AddonEnv = require("addon_env")
local Callsite = require("ui.callsite")
local Taint = require("taint")

local M = {}

-- Localized: addon code may assign globals of the same names.
local type, tostring, pairs, rawget, unpack, setfenv = type, tostring, pairs, rawget, unpack, setfenv
local getmetatable = debug.getmetatable

-- Longest __index chain issecurevariable follows for a nil field.
local INDEX_DEPTH = 8

-- Calls fn(...) with fn's owner as the taint (kit code and string names inherit the caller's), then drops whatever taint
-- the call acquired. An error goes to the error handler and the call returns nothing.
local function call(w, fn, ...)
  local mark = Taint.push(w, fn)
  local results = w:try(fn, ...)
  Taint.pop(w, mark)
  if results[1] then
    return unpack(results, 2, results.n)
  end
end

-- The table the slot of tbl[key] lives in: tbl, or (when the field is nil) the __index table that holds it.
local function slotTable(tbl, key)
  for _ = 1, INDEX_DEPTH do
    if tbl == _G or rawget(tbl, key) ~= nil then
      return tbl
    end
    local mt = getmetatable(tbl)
    local index = type(mt) == "table" and rawget(mt, "__index")
    if type(index) ~= "table" then
      return tbl
    end
    tbl = index
  end
  return tbl
end

-- source: assumed (row TS2) isSecure, taintingAddon from the slot; the addon view stands for _G.
local function issecurevariable(w, tbl, name)
  if name == nil then
    tbl, name = _G, tbl
  end
  if type(tbl) ~= "table" then
    error("bad argument #1 to 'issecurevariable' (table expected, got " .. type(tbl) .. ")", Callsite.level())
  elseif type(name) == "number" then
    name = tostring(name)
  elseif type(name) ~= "string" then
    error("bad argument #2 to 'issecurevariable' (string expected, got " .. type(name) .. ")", Callsite.level())
  end
  if w.addonEnvs and w.addonEnvs[tbl] then
    tbl = _G
  end
  local taint = Taint.slotOf(w, slotTable(tbl, name), name)
  return taint == nil, taint
end

function M.install(w)
  -- source: assumed (row TS1, "execution becomes 'tainted' as soon as it reads data or code introduced by a third party")
  -- the addon view's loadstring calls this: a chunk built by tainted execution (an addon's or a macro's, not
  -- forceinsecure's) keeps that taint when it runs later as a callback; a secure builder leaves it unowned.
  w.taint.chunk = function(fn, env)
    local taint = Taint.current(w)
    if taint and taint ~= Taint.FORCED then
      w.taint.owners[fn] = taint
    end
    return setfenv(fn, env)
  end
  -- source: assumed (row TS1) secure while no addon code runs.
  w:install("issecure", function()
    return Taint.current(w) == nil
  end)
  w:install("issecurevariable", function(tbl, name)
    return issecurevariable(w, tbl, name)
  end)
  -- source: `blizzard_uiparentpanelmanager/shared/uiparentpanelmanager.lua:282` (securecall with a global name),
  -- `blizzard_chatframebase/shared/chatframefilters.lua:23` (securecallfunction); the taint restore is assumed (row TS5).
  -- A global name resolves as addon code sees it, so a host-only one (require, io, ...) is not found.
  w:install("securecall", function(fn, ...)
    if type(fn) == "string" then
      fn = AddonEnv.global(w, fn)
    end
    return call(w, fn, ...)
  end)
  w:install("securecallfunction", function(fn, ...)
    return call(w, fn, ...)
  end)
  -- source: `api/retail/FrameScript.lua` securecallmethod(object, method, arguments) -> results; retail
  -- `blizzard_sharedxmlbase/pools.lua:473` (`securecallmethod(pool, "Release", object, canFailToFindObject)` reads the
  -- method's result); the TS5 rules (taint restore, swallowed error) are assumed to hold as for securecallfunction.
  w:install("securecallmethod", function(object, method, ...)
    return call(w, object[method], object, ...)
  end)
  -- source: `blizzard_chatframebase/shared/chatframeutil.lua:790-811` (func(key, value, extra) per pair); an error in
  -- one pair does not stop the loop (assumed, row TS5).
  w:install("secureexecuterange", function(tbl, func, ...)
    for key, value in pairs(tbl) do
      call(w, func, key, value, ...)
    end
  end)
  -- source: `blizzard_framexml/securetemplates.lua:752` (forceinsecure before running code Blizzard does not trust).
  w:install("forceinsecure", function()
    Taint.force(w)
  end)
end

return M
