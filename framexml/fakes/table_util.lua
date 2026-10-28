-- Table and math helpers addons call: CopyTable, CountTable, tDeleteItem, Lerp, Saturate, PercentageBetween and nop.
-- Kit-authored bodies over row W71. tCount is not installed: the client defines no such global.
local M = {}

-- Localized: addon code may assign globals named pairs or type.
local next, pairs, type = next, pairs, type
local remove = table.remove

local Core = require("framexml.fakes.core")

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

-- source: row W71 (confirmed) CountTable is table.count: every key, not only the array part.
local function countTable(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end

  return count
end

-- source: row W71 (confirmed) tDeleteItem is table.removevalue; that it removes every match and answers how many is
-- assumed (the engine function has no Lua body).
local function deleteItem(tbl, item)
  local removed = 0
  for index = #tbl, 1, -1 do
    if tbl[index] == item then
      remove(tbl, index)
      removed = removed + 1
    end
  end

  return removed
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

-- source: assumed the engine's table.isempty is true when the table has no key (blizzard_sharedxmlbase/tableutil.lua:19 aliases
-- it as TableIsEmpty; the docs give only `table` in and a boolean out). The retail extract has it and the tbc one does not.
local function isEmpty(tbl)
  return next(tbl) == nil
end

function M.install(w)
  w:install("table.isempty", isEmpty, { gate = "framexml", flavors = { "retail", "forever" } })
  w:install("CopyTable", copyTable, KETHO_GATE)
  -- The row gives no flavor limit and forever lists these four as Lua functions, not FrameXML ones: every flavor gets them.
  w:install("CountTable", countTable, Core.GATE)
  w:install("tDeleteItem", deleteItem, Core.GATE)
  w:install("Lerp", lerp, Core.GATE)
  w:install("Saturate", saturate, Core.GATE)
  w:install("PercentageBetween", percentageBetween, KETHO_GATE)
  w:install("nop", nop, KETHO_GATE)
end

return M
