-- Loads Blizzard_APIDocumentationGenerated files into plain tables inside a sandbox.
-- Docs reference Enum.X.Y and Constants.X.Y defined in other files, so loading repeats until those values settle.
local M = {}

local fs = require("fs")

local MAX_PASSES = 10
local BYTECODE_MARK = 27 -- "\27Lua": a precompiled chunk could escape the sandbox on 5.1.
local META_FIELDS = { "NumValues", "MinValue", "MaxValue" }
local ROOTS = { "Enum", "Constants" }

-- Two-level proxy: root.Group returns a table; root.Group.Name returns the collected value, else 0.
local function proxy(groups)
  return setmetatable({}, {
    __index = function(_, group)
      local known = groups[group] or {}
      return setmetatable({}, {
        __index = function(_, name)
          local value = known[name]
          if value == nil then
            return 0
          end
          return value
        end,
      })
    end,
  })
end

local function compile(src, chunkName, env)
  if src:byte(1) == BYTECODE_MARK then
    return nil, chunkName:sub(2) .. ": precompiled chunks are not allowed"
  end
  local setfenv = rawget(_G, "setfenv")
  if setfenv then
    local fn, err = loadstring(src, chunkName)
    return fn and setfenv(fn, env), err
  end
  return load(src, chunkName, "t", env)
end

-- Runs one doc file in a fresh sandbox. Returns true plus the captured tables, or false plus the error.
local function runFile(dir, name, values)
  local captured = {}
  local env = {
    APIDocumentation = {
      AddDocumentationTable = function(_, t)
        captured[#captured + 1] = t
      end,
    },
    Enum = proxy(values.Enum),
    Constants = proxy(values.Constants),
  }
  local src, err = fs.readFile(dir .. "/" .. name)
  local fn
  if src then
    fn, err = compile(src, "@" .. name, env)
  end
  if not fn then
    return false, err
  end
  local ok, runErr = pcall(fn)
  if not ok then
    return false, runErr
  end
  return true, captured
end

local function loadPass(dir, names, values)
  local entries, errors = {}, {}
  for _, name in ipairs(names) do
    local ok, result = runFile(dir, name, values)
    if ok then
      for _, doc in ipairs(result) do
        entries[#entries + 1] = { file = name, doc = doc }
      end
    else
      errors[#errors + 1] = { file = name, err = tostring(result) }
    end
  end
  return entries, errors
end

local function group(values, root, name)
  values[root][name] = values[root][name] or {}
  return values[root][name]
end

-- Enum.<Name>.<Field> = EnumValue, plus Enum.<Name>Meta.{NumValues,MinValue,MaxValue} as the game exposes.
local function collectEnumeration(values, t)
  local fields = group(values, "Enum", t.Name)
  for _, field in ipairs(t.Fields or {}) do
    fields[field.Name] = field.EnumValue
  end
  local meta = group(values, "Enum", t.Name .. "Meta")
  for _, key in ipairs(META_FIELDS) do
    meta[key] = t[key]
  end
end

-- Constants.<Name>.<Value name> = Value; a string Value typed as a known enumeration becomes that enum's value.
local function collectConstants(values, t)
  local consts = group(values, "Constants", t.Name)
  for _, v in ipairs(t.Values or {}) do
    local enum = values.Enum[v.Type]
    if type(v.Value) == "string" and enum then
      consts[v.Name] = enum[v.Value]
    else
      consts[v.Name] = v.Value
    end
  end
end

local function eachTable(entries, kind, fn)
  for _, entry in ipairs(entries) do
    for _, t in ipairs(entry.doc.Tables or {}) do
      if t.Type == kind then
        fn(t)
      end
    end
  end
end

local function collect(entries)
  local values = { Enum = {}, Constants = {} }
  eachTable(entries, "Enumeration", function(t)
    collectEnumeration(values, t)
  end)
  eachTable(entries, "Constants", function(t)
    collectConstants(values, t)
  end)
  return values
end

local function addChanged(changed, seen, root, a, b)
  for groupName, fields in pairs(a) do
    for name, value in pairs(fields) do
      local key = root .. "." .. groupName .. "." .. name
      if (b[groupName] or {})[name] ~= value and not seen[key] then
        seen[key] = true
        changed[#changed + 1] = key
      end
    end
  end
end

-- Sorted "Root.Group.Name" keys whose value differs between two collections.
local function changedKeys(old, new)
  local changed, seen = {}, {}
  for _, root in ipairs(ROOTS) do
    addChanged(changed, seen, root, old[root], new[root])
    addChanged(changed, seen, root, new[root], old[root])
  end
  table.sort(changed)
  return changed
end

local function luaFiles(dir)
  local names = {}
  for _, name in ipairs(fs.list(dir)) do
    if name:match("%.lua$") then
      names[#names + 1] = name
    end
  end
  return names
end

-- Returns entries { file, doc }, errors { file, err }, report { passes, settled, notes }.
function M.loadDir(dir)
  if not fs.isdir(dir) then
    error("not a directory: " .. tostring(dir), 2)
  end
  local names = luaFiles(dir)
  local values = { Enum = {}, Constants = {} }
  local report = { passes = 0, settled = false, notes = {} }
  local entries, errors, changed
  for pass = 1, MAX_PASSES do
    entries, errors = loadPass(dir, names, values)
    local collected = collect(entries)
    changed = changedKeys(values, collected)
    values = collected
    report.passes = pass
    if #changed == 0 then
      report.settled = true
      return entries, errors, report
    end
  end
  for _, key in ipairs(changed) do
    report.notes[#report.notes + 1] = "not settled after " .. MAX_PASSES .. " passes: " .. key
  end
  entries, errors = loadPass(dir, names, values)
  return entries, errors, report
end

return M
