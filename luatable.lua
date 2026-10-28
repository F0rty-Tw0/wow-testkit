-- The engine's table.* extensions, as the LuaTableExtensions API documentation lists them (retail 70575 extract and
-- forever's generated data): contains, count, create, indexof, freeze, keys, getcountinfo, values, isempty, isfrozen,
-- removeunordered and removevalue. luaapi.lua installs them per flavor; framexml/fakes/table_util.lua reuses count and
-- removevalue for CountTable and tDeleteItem. Row BU20 of docs/client-sources.md.
local M = {}

-- Localized: addon code may assign globals named next, pairs or type.
local next, pairs, type = next, pairs, type
local remove = table.remove

-- Weak keys: a frozen table that nothing else holds is collected.
local frozen = setmetatable({}, { __mode = "k" })

function M.contains(tbl, value)
  for _, v in pairs(tbl) do
    if v == value then
      return true
    end
  end

  return false
end

-- source: row W71 (confirmed) CountTable is table.count: every key, not only the array part.
function M.count(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end

  return count
end

-- The size hints only preallocate storage; a Lua table needs none.
function M.create()
  return {}
end

-- From index 1 up to the first nil, the order the docs give.
function M.indexof(tbl, value)
  local index = 1
  while tbl[index] ~= nil do
    if tbl[index] == value then
      return index
    end
    index = index + 1
  end

  return nil
end

-- assumed: the docs say "marks a table as frozen, preventing any modifications"; a plain Lua 5.1 table cannot trap a write
-- to a key it already holds, so the kit records the mark (isfrozen) and does not refuse writes.
function M.freeze(tbl)
  frozen[tbl] = true
  return tbl
end

function M.isfrozen(tbl)
  return frozen[tbl] == true
end

-- The docs leave the order unspecified; pairs order it is.
function M.keys(tbl)
  local keys = {}
  for key in pairs(tbl) do
    keys[#keys + 1] = key
  end

  return keys
end

function M.values(tbl)
  local values = {}
  for _, value in pairs(tbl) do
    values[#values + 1] = value
  end

  return values
end

-- A positive integral key is a number above zero with no fraction (2 and 2.0 are one key).
function M.getcountinfo(tbl)
  local entries, positive, max = 0, 0, 0
  for key in pairs(tbl) do
    entries = entries + 1
    if type(key) == "number" and key > 0 and key % 1 == 0 then
      positive = positive + 1
      max = key > max and key or max
    end
  end

  return entries, positive, max
end

-- assumed: true when the table has no key (blizzard_sharedxmlbase/tableutil.lua:19 aliases it as TableIsEmpty; the docs
-- say only "contains no entries").
function M.isempty(tbl)
  return next(tbl) == nil
end

-- The last value takes the removed one's place; an index outside the array, or an empty array, removes nothing.
function M.removeunordered(tbl, index)
  local last = #tbl
  index = index or last
  if index < 1 or index > last then
    return nil
  end

  local value = tbl[index]
  tbl[index] = tbl[last]
  tbl[last] = nil
  return value
end

-- source: row W71 (confirmed) tDeleteItem is table.removevalue; that it removes every match and answers how many is
-- assumed (the engine function has no Lua body).
function M.removevalue(tbl, value)
  local removed = 0
  for index = #tbl, 1, -1 do
    if tbl[index] == value then
      remove(tbl, index)
      removed = removed + 1
    end
  end

  return removed
end

return M
