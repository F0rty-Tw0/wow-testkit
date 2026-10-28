-- Table and math helpers addons call: CopyTable, CountTable, tDeleteItem, Lerp, Saturate, PercentageBetween and nop.
-- Kit-authored bodies over row W71; CountTable and tDeleteItem are luatable.lua's count and removevalue. tCount is not
-- installed: the client defines no such global.
local M = {}

-- Localized: addon code may assign globals named pairs or type.
local pairs, type = pairs, type

local Core = require("framexml.fakes.core")
local LuaTable = require("luatable")

-- Ketho's FrameXML list decides which flavors get these.
local KETHO_GATE = { gate = "framexml", flavors = {} }

-- source: row W71 (confirmed) blizzard_sharedxmlbase/tableutil.lua:218 copies every key into a plain table, nested tables
-- too unless shallow; the copy has no metatable.
local function copyTable(settings, shallow)
  local copy = {}
  for key, value in pairs(settings) do
    copy[key] = (type(value) == "table" and not shallow) and copyTable(value) or value
  end

  return copy
end

-- source: row W71 (confirmed) Lerp is math.lerp and Saturate is math.saturate (engine); the usual definitions.
local function lerp(startValue, endValue, amount)
  return (1 - amount) * startValue + amount * endValue
end

local function saturate(value)
  return value < 0 and 0 or (value > 1 and 1 or value)
end

-- source: row W71 (confirmed) blizzard_sharedxmlbase/mathutil.lua:49 0 for an empty range, else the fraction.
local function percentageBetween(value, startValue, endValue)
  if startValue == endValue then
    return 0
  end

  return (value - startValue) / (endValue - startValue)
end

-- source: row W71 (confirmed) blizzard_sharedxmlbase/environmentutil.lua:5 does nothing.
local function nop() end

function M.install(w)
  w:install("CopyTable", copyTable, KETHO_GATE)
  -- The row gives no flavor limit and forever lists these four as Lua functions, not FrameXML ones: every flavor gets them.
  w:install("CountTable", LuaTable.count, Core.GATE)
  w:install("tDeleteItem", LuaTable.removevalue, Core.GATE)
  w:install("Lerp", lerp, Core.GATE)
  w:install("Saturate", saturate, Core.GATE)
  w:install("PercentageBetween", percentageBetween, KETHO_GATE)
  w:install("nop", nop, KETHO_GATE)
end

return M
