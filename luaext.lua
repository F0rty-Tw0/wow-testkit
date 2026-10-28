-- WoW's Lua extensions: the global string/table/math aliases, wipe/strsplit/strjoin/strtrim/tContains,
-- hooksecurefunc, debugstack, the error handler, debugprofilestop, GetTime and C_Timer. The secure-execution APIs
-- (issecure, securecall, forceinsecure, ...) are taint_api.lua.
-- Installed into every world by world.lua (gate "none"; C_Timer through gate "api").
local AddonEnv = require("addon_env")
local Taint = require("taint")

local M = {}

local unpack = unpack
local select = select
-- Localized: addon code may assign a global named os.
local osClock = os.clock

local DEFAULT_TRIM = " \t\r\n"
local MS_PER_SECOND = 1000

local function pack(...)
  return { n = select("#", ...), ... }
end

-- WoW's aliases match the host library functions exactly, so the host function is installed as is.
-- unpack: Lua 5.1 already has it with WoW's semantics; installed only when the host lacks it.
local ALIASES = {
  strmatch = string.match,
  strfind = string.find,
  strsub = string.sub,
  strlen = string.len,
  strlower = string.lower,
  strupper = string.upper,
  format = string.format,
  tinsert = table.insert,
  tremove = table.remove,
  floor = math.floor,
  ceil = math.ceil,
  abs = math.abs,
  min = math.min,
  max = math.max,
  time = os.time,
  date = os.date,
}
M.ALIASES = ALIASES

local function escapeClass(chars)
  return (chars:gsub("[%%%]%^%-]", "%%%0"))
end

function M.wipe(t)
  for k in pairs(t) do
    t[k] = nil
  end
  return t
end

-- A number argument reads as its string form, as a C string argument does (lua_tolstring): the docs type these as
-- Lua strings (api/retail/StringUtil.lua string.trim, wiki API_strsplit). Other non-strings still raise.
local function stringArg(value)
  if type(value) == "number" then
    return tostring(value)
  end

  return value
end

-- strsplit(sep, str, pieces): sep is a set of single chars; at most pieces values, the last keeping the rest.
function M.strsplit(sep, str, pieces)
  local class = "[" .. escapeClass(stringArg(sep)) .. "]"
  str = stringArg(str)
  local out, start = {}, 1
  while not pieces or #out < pieces - 1 do
    local first, last = str:find(class, start)
    if not first then
      break
    end
    out[#out + 1] = str:sub(start, first - 1)
    start = last + 1
  end
  out[#out + 1] = str:sub(start)
  return unpack(out, 1, #out)
end

function M.strjoin(sep, ...)
  local parts = pack(...)
  return table.concat(parts, sep, 1, parts.n)
end

function M.strtrim(str, chars)
  local class = "[" .. escapeClass(stringArg(chars or DEFAULT_TRIM)) .. "]"
  local text = stringArg(str)

  return (text:gsub("^" .. class .. "+", ""):gsub(class .. "+$", ""))
end

function M.tContains(tbl, item)
  for _, v in ipairs(tbl) do
    if v == item then
      return true
    end
  end
  return false
end

-- hooksecurefunc([tbl,] name, hook): tbl[name] becomes original-then-hook; the hook runs in "addon" context and
-- its errors go to the error handler, so the original's results still return. A global name must exist as addon code
-- sees it (AddonEnv.global), so a host-only global (require, io, ...) is refused and never rewritten; the host value is
-- what gets wrapped, so kit code reading a hooked global (setfenv, loadstring, ...) keeps the host function's behaviour.
local function hooksecurefunc(w, tbl, name, hook)
  local original
  if type(tbl) == "table" then
    original = tbl[name]
  else
    tbl, name, hook = _G, tbl, name
    original = AddonEnv.global(w, name) ~= nil and _G[name] or nil
  end
  if type(original) ~= "function" then
    error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 3)
  end
  local wrapper = function(...)
    local results = pack(original(...))
    w:callAsAddon(hook, ...)
    return unpack(results, 1, results.n)
  end
  -- source: assumed (row TS7) installing a hook leaves the slot secure; the hook runs after the original with its own taint.
  Taint.secure(w, w.rawWrite, w, tbl, name, wrapper)
end

local function installErrorHandler(w)
  w:install("geterrorhandler", function()
    return w.errorHandler
  end)
  w:install("seterrorhandler", function(fn)
    w.errorHandler = fn
  end)
end

local function installTimers(w)
  w:install("C_Timer.After", function(seconds, callback)
    -- The wrapper drops the timer argument; it runs with the callback's owner.
    local wrapper = function()
      callback()
    end
    w:schedule(seconds, Taint.adopt(w, wrapper, callback), 1)
  end, { gate = "api" })
  w:install("C_Timer.NewTimer", function(seconds, callback)
    return w:schedule(seconds, callback, 1)
  end, { gate = "api" })
  w:install("C_Timer.NewTicker", function(seconds, callback, iterations)
    return w:schedule(seconds, callback, iterations)
  end, { gate = "api" })
end

function M.install(w)
  for name, fn in pairs(ALIASES) do
    w:install(name, fn)
  end
  if rawget(_G, "unpack") == nil then
    w:install("unpack", rawget(table, "unpack"))
  end
  for _, name in ipairs({ "wipe", "strsplit", "strjoin", "strtrim", "tContains" }) do
    w:install(name, M[name])
  end
  w:install("hooksecurefunc", function(tbl, name, hook)
    hooksecurefunc(w, tbl, name, hook)
  end)
  -- An engine function with no Lua source (row W72, assumed): debugstack answers an empty stack because the kit keeps no
  -- stack text of its own.
  w:install("debugstack", function()
    return ""
  end)
  w:install("debugprofilestop", function()
    return osClock() * MS_PER_SECOND
  end)
  w:install("GetTime", function()
    return w.now
  end)
  installErrorHandler(w)
  installTimers(w)
end

return M
