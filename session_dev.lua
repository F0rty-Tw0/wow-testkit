-- Developer report: per addon, in load order, its load time and heap growth (w.dev.loads, addon.lua), the widgets and
-- unscripted calls credited to it (w.dev.widgets, w.dev.unscripted, ui/callsite.lua) and the nil globals its errors
-- name. Every API of the flavor's data is installed as a stub, so a nil global is one the data lacks, a secureOnly one
-- or the addon's own typo. Reads w.dev and w.errors only.
local M = {}

local NOTES = { "loadMs: kit CPU time (os.clock), not client time", "memoryKb: heap growth during load, kit allocations included, an estimate" }

-- Lua 5.1's messages for a nil global; "call field" and "call local" ones name no global, so they are not listed.
local MISSING = {
  { kind = "call", pattern = "attempt to call global '([^']+)' %(a nil value%)" },
  { kind = "index", pattern = "attempt to index global '([^']+)' %(a nil value%)" },
}

local function byCountThenName(a, b)
  if a.count ~= b.count then
    return a.count > b.count
  end
  return a.name < b.name
end

local function widgetsOf(counts)
  local list = {}
  for typeName, count in pairs(counts or {}) do
    list[#list + 1] = { type = typeName, count = count }
  end
  table.sort(list, function(a, b)
    return a.type < b.type
  end)
  return list
end

local function unscriptedOf(counts)
  local list = {}
  for name, count in pairs(counts or {}) do
    list[#list + 1] = { name = name, count = count }
  end
  table.sort(list, byCountThenName)
  return list
end

-- The nil global an error message names: name, kind; nil when it names none.
local function missingIn(message)
  for _, rule in ipairs(MISSING) do
    local name = tostring(message):match(rule.pattern)
    if name then
      return name, rule.kind
    end
  end
  return nil
end

-- { [addon] = list of { name, kind, count, file } }, one entry per global and kind, file the first that named it.
local function missingByAddon(errors)
  local lists, seen = {}, {}
  for _, err in ipairs(errors) do
    local addon, file = (err.source or ""):match("^addon:([^/]+)/(.+)$")
    local name, kind = missingIn(err.message)
    if addon and name then
      local key = addon .. "\0" .. kind .. "\0" .. name
      local entry = seen[key]
      if entry then
        entry.count = entry.count + 1
      else
        entry = { name = name, kind = kind, count = 1, file = file }
        seen[key] = entry
        lists[addon] = lists[addon] or {}
        table.insert(lists[addon], entry)
      end
    end
  end
  return lists
end

-- { addons, notes }: addons in load order, each { name, loadMs, memoryKb, widgets, unscripted, missing }; lists sort
-- by count descending then name, widgets by type.
function M.report(w)
  local dev = w.dev
  local missing = missingByAddon(w.errors)
  local addons = {}
  for i, load in ipairs(dev.loads) do
    local list = missing[load.name] or {}
    table.sort(list, byCountThenName)
    addons[i] = {
      name = load.name,
      loadMs = load.loadMs,
      memoryKb = load.memoryKb,
      widgets = widgetsOf(dev.widgets[load.name]),
      unscripted = unscriptedOf(dev.unscripted[load.name]),
      missing = list,
    }
  end
  local notes = {}
  for i, note in ipairs(NOTES) do
    notes[i] = note
  end
  return { addons = addons, notes = notes }
end

return M
