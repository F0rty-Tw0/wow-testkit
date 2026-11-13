-- WoW's Lua extensions: the global string/table/math aliases, wipe/strsplit/strjoin/strtrim/tContains,
-- hooksecurefunc, debugstack, the error handler, debugprofilestop, GetTime and C_Timer. The secure-execution APIs
-- (issecure, securecall, forceinsecure, ...) are taint_api.lua.
-- Installed into every world by world.lua (gate "none"; C_Timer through gate "api").
local AddonEnv = require("addon_env")
local AddonModules = require("addon_modules")
local Names = require("addon_env_names")
local Taint = require("taint")

local M = {}

local unpack = unpack
local select = select
-- Localized: addon code may assign a global named os.
local osClock = os.clock

local DEFAULT_TRIM = " \t\r\n"
local MS_PER_SECOND = 1000
local hostFormat = string.format
local POSITIONAL = "%%%d+%$"
local POSITIONAL_SPEC = "^(%d+)%$([-+ #0]*%d*%.?%d*%a)()"
local SEQUENTIAL_SPEC = "^([-+ #0]*%d*%.?%d*%a)()"

-- C99's %F is %f with upper-case INF/NAN; Lua 5.1's format lacks it (row W84).
local function hostSpec(spec)
  return (spec:gsub("F$", "f"))
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- WoW's format: the host's, plus positional specs `%<n>$<spec>` taking argument n (row W84: the client's own strings
-- reorder arguments, forever 70862 strings/enUS.lua "%2$02d/%1$d/20%3$02d"). A spec without n takes the next argument.
-- %F formats as %f (tbc paperdollframe.lua CharacterDamageFrame_OnEnter "%.2F").
function M.format(fmt, ...)
  if type(fmt) ~= "string" or not (fmt:find(POSITIONAL) or fmt:find("F", 1, true)) then
    return hostFormat(fmt, ...)
  end
  local args, parts, picked, nextArg, at = pack(...), {}, {}, 0, 1
  while true do
    local start = fmt:find("%", at, true)
    if not start then
      parts[#parts + 1] = fmt:sub(at)
      break
    end
    parts[#parts + 1] = fmt:sub(at, start - 1)
    local index, spec, stop = fmt:match(POSITIONAL_SPEC, start + 1)
    if fmt:sub(start + 1, start + 1) == "%" then
      parts[#parts + 1], at = "%%", start + 2
    elseif index then
      picked[#picked + 1] = tonumber(index)
      parts[#parts + 1], at = "%" .. hostSpec(spec), stop
    else
      local plain, after = fmt:match(SEQUENTIAL_SPEC, start + 1)
      nextArg = nextArg + 1
      picked[#picked + 1] = nextArg
      if plain then
        parts[#parts + 1], at = "%" .. hostSpec(plain), after
      else
        parts[#parts + 1], at = "%", start + 1
      end
    end
  end
  local values = {}
  for i, index in ipairs(picked) do
    values[i] = args[index]
  end
  return hostFormat(table.concat(parts), unpack(values, 1, #picked))
end

-- WoW's aliases match the host library functions exactly, so the host function is installed as is (format: WoW's, above).
-- unpack: Lua 5.1 already has it with WoW's semantics; installed only when the host lacks it.
local ALIASES = {
  strmatch = string.match,
  strfind = string.find,
  strsub = string.sub,
  strlen = string.len,
  strlower = string.lower,
  strupper = string.upper,
  format = M.format,
  ["string.format"] = M.format,
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
-- sees it (AddonEnv.global), so a host-only global (require, io, ...) is refused and never rewritten. A base-library
-- name (Names.KEPT: type, setfenv, ...) hooked on _G or the addon view wraps the view's value and stays in the view, so
-- the addon's calls fire the hook and kit code reading _G keeps the host function; so does a name the view answers apart
-- from _G (Forever's require). Any other name hooked on the view hooks _G's slot, the one global addon and kit code both
-- call (the client has one _G).
local function hooksecurefunc(w, tbl, name, hook)
  local original
  if type(tbl) == "table" then
    original = tbl[name]
  else
    tbl, name, hook = _G, tbl, name
    original = AddonEnv.global(w, name)
  end
  local viewed = tbl == _G or w.addonEnvs and w.addonEnvs[tbl]
  local kept = viewed and (Names.KEPT[name] or rawget(_G, name) ~= original)
  if kept then
    original = AddonEnv.global(w, name)
  end
  if type(original) ~= "function" then
    error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 3)
  end
  local wrapper = function(...)
    local results = pack(original(...))
    w:callAsAddon(hook, ...)
    return unpack(results, 1, results.n)
  end
  if kept then
    return AddonEnv.keep(w, name, wrapper)
  elseif w.addonEnvs and w.addonEnvs[tbl] then
    tbl = _G
  end
  -- source: assumed (row TS7) installing a hook leaves the slot's taint as it was (a secure slot stays secure, one an addon
  -- wrote stays that addon's); the hook runs after the original with its own taint.
  local earlier = Taint.slotOf(w, tbl, name)
  Taint.secure(w, w.rawWrite, w, tbl, name, wrapper)
  if earlier then
    w.taint.slots[tbl][name] = earlier
  end
end

-- source: assumed (row G21) the client's math extensions (MathUtil.lua aliases them at load; no source gives their bodies):
-- the usual meanings. round is half away from zero; wrap is the half-open [min, max) interval MathUtil.lua's comment names.
local function clamp(value, low, high)
  return math.min(math.max(value, low), high)
end

local MATH_EXTENSIONS = {
  clamp = clamp,
  lerp = function(from, to, amount)
    return from + (to - from) * amount
  end,
  round = function(value)
    return value < 0 and -math.floor(-value + 0.5) or math.floor(value + 0.5)
  end,
  sign = function(value)
    return value > 0 and 1 or value < 0 and -1 or 0
  end,
  saturate = function(value)
    return clamp(value, 0, 1)
  end,
  normalize = function(value, from, to)
    return (value - from) / (to - from)
  end,
  wrap = function(value, low, high)
    return low + (value - low) % (high - low)
  end,
}

local function installErrorHandler(w)
  w:install("geterrorhandler", function()
    return w.errorHandler
  end)
  w:install("seterrorhandler", function(fn)
    w.errorHandler = fn
  end)
end

-- source: confirmed (row G51) forever 70862 blizzard_apidocumentationgenerated/timedsignalmapapidocumentation.lua: a map
-- of integer keys, each due at an absolute GetTime() time; a due key leaves the map and goes to the callback; SignalAt and
-- SignalAfter replace a key's schedule. Assumed: a plain table (timerutil.lua:17 adds a method to it), no secret values.
local function newTimedSignalMap(w, callback)
  local timers = {}
  local map = {}
  local function cancel(key)
    if timers[key] then
      timers[key]:Cancel()
      timers[key] = nil
    end
  end
  function map:SignalAt(key, time)
    cancel(key)
    timers[key] = w:schedule(time - w.now, function()
      timers[key] = nil
      callback(key)
    end, 1)
  end
  function map:SignalAfter(key, seconds)
    self:SignalAt(key, w.now + seconds)
  end
  function map:CancelSignal(key)
    cancel(key)
  end
  function map:CancelAllSignals()
    for key in pairs(timers) do
      cancel(key)
    end
  end
  function map:HasSignal(key)
    return timers[key] ~= nil
  end
  function map:GetSignalTime(key)
    return timers[key] and timers[key].due
  end
  function map:GetSignalCount()
    local count = 0
    for _ in pairs(timers) do
      count = count + 1
    end
    return count
  end
  function map:GetNextSignal()
    local nextKey, nextTime
    for key, timer in pairs(timers) do
      if nextTime == nil or timer.due < nextTime then
        nextKey, nextTime = key, timer.due
      end
    end
    return nextKey, nextTime
  end
  return map
end

-- source: confirmed (row G52) the method names, forever 70862 secondsformatterapidocumentation.lua: Set<P> stores a
-- setting that Get<P> / Can<P> / Evaluate<P> read back, Reset clears them. Assumed: Format and FormatZero answer whole
-- seconds as "<n>s" (the engine's unit and abbreviation rules have no source the kit can read).
local FORMATTER_SETTINGS = {
  "ApproximationSeconds",
  "CanRoundUpIntervals",
  "CanRoundUpLastUnit",
  "ConvertToLower",
  "DefaultAbbreviation",
  "DesiredUnitCount",
  "DesiredUnitCountCurve",
  "MaxInterval",
  "MaxIntervalCurve",
  "MillisecondsThreshold",
  "MinInterval",
  "MinIntervalCurve",
  "Rounding",
  "StripIntervalWhitespace",
}

local function newSecondsFormatter()
  local settings = {}
  local formatter = {}
  for _, name in ipairs(FORMATTER_SETTINGS) do
    local bare = name:gsub("^Can", "")
    formatter["Set" .. name] = function(_, value)
      settings[name] = value
    end
    formatter[(name:find("^Can") and "" or "Get") .. name] = function()
      return settings[name]
    end
    formatter["Evaluate" .. bare] = function()
      return settings[name]
    end
  end
  formatter.CanApproximate = function()
    return settings.ApproximationSeconds ~= nil
  end
  formatter.Reset = function()
    settings = {}
  end
  formatter.Format = function(_, seconds)
    return math.floor(seconds + 0.5) .. "s"
  end
  formatter.FormatZero = function()
    return "0s"
  end
  return formatter
end

-- source: assumed (row G53) securecopy(value) answers a deep copy of a table (keys and values copied, cycles kept) and
-- any other value as is; the options argument is ignored.
local function secureCopy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[secureCopy(key, seen)] = secureCopy(item, seen)
  end
  return copy
end

local function installTimers(w)
  w:install("C_StringUtil.CreateSecondsFormatter", newSecondsFormatter, { gate = "api" })
  w:install("securecopy", function(value)
    return secureCopy(value)
  end, { gate = "api" })
  -- grug: forever only by name, as G48: api/forever predates the doc set that lists it.
  if w.flavor == "forever" then
    -- source: row L9 (confirmed) forever's Gamepad addons call import at load (blizzard_gamepadsmartnavigation/
    -- utility.lua:3); no doc lists it and the tbc extract never calls it.
    w:install("import", function(path)
      return AddonModules.import(w, path)
    end)
    w:install("C_Timer.NewTimedSignalMap", function(callback)
      return newTimedSignalMap(
        w,
        Taint.adopt(w, function(key)
          callback(key)
        end, callback)
      )
    end)
  end
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
  for name, fn in pairs(MATH_EXTENSIONS) do
    w:install("math." .. name, fn)
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
