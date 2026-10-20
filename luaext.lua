-- WoW's Lua extensions: the global string/table/math aliases, wipe/strsplit/strjoin/strtrim/tContains,
-- hooksecurefunc, securecall, issecurevariable, the error handler, debugprofilestop, GetTime and C_Timer.
-- Installed into every world by world.lua (gate "none"; C_Timer through gate "api").
local M = {}

local unpack = unpack
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
-- its errors go to the error handler, so the original's results still return.
local function hooksecurefunc(w, tbl, name, hook)
  if type(tbl) ~= "table" then
    tbl, name, hook = _G, tbl, name
  end
  local original = tbl[name]
  if type(original) ~= "function" then
    error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 3)
  end
  w:rawWrite(tbl, name, function(...)
    local results = pack(original(...))
    w:callAsAddon(hook, ...)
    return unpack(results, 1, results.n)
  end)
end

-- securecall(fn | globalName, ...): fn's results; on error, reports it to the error handler and returns nothing.
-- The error behaviour is inferred from the game (securecall never propagates), not from documentation.
local function securecall(w, fn, ...)
  if type(fn) == "string" then
    fn = _G[fn]
  end
  local results = w:try(fn, ...)
  if results[1] then
    return unpack(results, 2, results.n)
  end
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
    w:schedule(seconds, function()
      callback()
    end, 1)
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
  w:install("securecall", function(fn, ...)
    return securecall(w, fn, ...)
  end)
  w:install("issecurevariable", function()
    return true, nil
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
