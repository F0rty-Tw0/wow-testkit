-- Ketho's LuaAPI names (the `lua` list in api/<flavor>/globals.lua) that the world does not define yet: WoW's
-- global aliases of the standard library, its degree-based trig globals, string/table extensions, the bit library
-- and Forever's math/table helpers. Installed per flavor (only that flavor's names) after luaext, so names the host
-- or the world already defines are kept. A name without an implementation here becomes a stub that records
-- w.unscripted and returns nil.
local M = {}

local Luaext = require("luaext")
local LuaTable = require("luatable")
local WorldApi = require("world_api")

-- Localized: addon code may assign a global named select.
local select = select
local TWO_32 = 2 ^ 32
local BITS = 32
local ROUND_HALF = 0.5

-- bit: WoW's bitlib works on 32-bit ints (bit.lshift(0x80000000, 1) == 0). Results here are unsigned 32-bit.
local function u32(x)
  return math.floor(x) % TWO_32
end

-- A variadic bitwise op: keep(bitA, bitB) decides each result bit.
local function bitwise(keep)
  return function(a, ...)
    local result = u32(a)
    for i = 1, select("#", ...) do
      local x, y, out, place = result, u32((select(i, ...))), 0, 1
      for _ = 1, BITS do
        local xb, yb = x % 2, y % 2
        if keep(xb, yb) then
          out = out + place
        end
        x, y, place = (x - xb) / 2, (y - yb) / 2, place * 2
      end
      result = out
    end
    return result
  end
end

local function rshift(a, n)
  return math.floor(u32(a) / 2 ^ n)
end

local function arshift(a, n)
  local x = u32(a)
  local shifted = rshift(x, n)
  if x >= 2 ^ (BITS - 1) then
    shifted = shifted + TWO_32 - 2 ^ (BITS - n)
  end
  return shifted
end

local BIT = {
  ["bit.band"] = bitwise(function(a, b)
    return a == 1 and b == 1
  end),
  ["bit.bor"] = bitwise(function(a, b)
    return a == 1 or b == 1
  end),
  ["bit.bxor"] = bitwise(function(a, b)
    return a ~= b
  end),
  ["bit.bnot"] = function(a)
    return TWO_32 - 1 - u32(a)
  end,
  ["bit.lshift"] = function(a, n)
    return u32(a) * 2 ^ n % TWO_32
  end,
  ["bit.rshift"] = rshift,
  ["bit.arshift"] = arshift,
  ["bit.mod"] = math.fmod,
}

-- WoW's global trig functions take and return degrees (math.* stays in radians).
local DEGREES = {
  sin = function(x)
    return math.sin(math.rad(x))
  end,
  cos = function(x)
    return math.cos(math.rad(x))
  end,
  tan = function(x)
    return math.tan(math.rad(x))
  end,
  asin = function(x)
    return math.deg(math.asin(x))
  end,
  acos = function(x)
    return math.deg(math.acos(x))
  end,
  atan = function(x)
    return math.deg(math.atan(x))
  end,
  atan2 = function(y, x)
    return math.deg(math.atan2(y, x))
  end,
}

local function strconcat(...)
  return Luaext.strjoin("", ...)
end

local ALIASES = {
  deg = math.deg,
  rad = math.rad,
  exp = math.exp,
  frexp = math.frexp,
  ldexp = math.ldexp,
  log = math.log,
  log10 = math.log10,
  sqrt = math.sqrt,
  random = math.random,
  fastrandom = math.random,
  mod = math.fmod,
  difftime = os.difftime,
  sort = table.sort,
  foreach = rawget(table, "foreach"),
  foreachi = rawget(table, "foreachi"),
  getn = rawget(table, "getn"),
  gmatch = string.gmatch,
  gsub = string.gsub,
  strbyte = string.byte,
  strchar = string.char,
  strrep = string.rep,
  strrev = string.reverse,
  strconcat = strconcat,
  ["string.concat"] = strconcat,
  ["string.join"] = Luaext.strjoin,
  ["string.split"] = Luaext.strsplit,
  ["string.trim"] = Luaext.strtrim,
  ["table.wipe"] = Luaext.wipe,
}

local HELPERS = {
  strsplittable = function(sep, str, pieces)
    return { Luaext.strsplit(sep, str, pieces) }
  end,
  strlenutf8 = function(str)
    return select(2, str:gsub("[^\128-\191]", ""))
  end,
  Round = function(value)
    return math.floor(value + ROUND_HALF)
  end,
  Clamp = function(value, low, high)
    return math.min(math.max(value, low), high)
  end,
  tIndexOf = LuaTable.indexof,
}
for name, fn in pairs(LuaTable) do
  HELPERS["table." .. name] = fn
end

-- The kit's function for a Ketho LuaAPI name, or nil when it has none.
local function implementation(name)
  return BIT[name] or DEGREES[name] or ALIASES[name] or HELPERS[name]
end
M.implementation = implementation

-- True when the kit implements this Ketho LuaAPI name (string.trim, table.count, ...).
function M.implements(name)
  return implementation(name) ~= nil
end

local function unscriptedStub(w, name)
  return function()
    WorldApi.markUnscripted(w, name)
  end
end

-- What the world installs for name: the kit's function, else a stub that records the call as unscripted.
function M.of(w, name)
  return implementation(name) or unscriptedStub(w, name)
end

-- Retail 70575's docs document every table.* extension, but the pinned mirror's list (12.1.0.69933) predates eight of them;
-- Blizzard's TableUtil aliases them (tContains = table.contains), so retail gets the rest too (row BU20).
local function installRetailTableExtensions(w)
  if w.flavor ~= "retail" then
    return
  end
  for name, fn in pairs(LuaTable) do
    local full = "table." .. name
    if not w.globals.lua[full] then
      w:install(full, fn)
    end
  end
end

function M.install(w)
  for name in pairs(w.globals.lua) do
    if not w:hostHas(name) then
      w:install(name, M.of(w, name))
    end
  end
  installRetailTableExtensions(w)
end

return M
