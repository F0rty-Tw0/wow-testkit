-- Saved variables of a session on disk: one file, <dir>/saved.lua, `return { Name = <literal> }` written by Serialize.
-- Like the client, the variables are written only when the session reloads or shuts down.
local M = {}

local Addon = require("addon")
local Console = require("session_console")
local Serialize = require("serialize")
local fs = require("fs")

-- Localized: addon code may assign globals with these names.
local concat, loadstring, pcall, select, setfenv, tostring, type = table.concat, loadstring, pcall, select, setfenv, tostring, type

local FILE = "saved.lua"
M.FILE = FILE
local TEMP_SUFFIX = ".tmp"
local PRECOMPILED = "\27"
local MAX_NAMED = 10 -- paths one console line names

-- The saved table of dir, or {} for a missing file; {} plus a warning for a file that does not load to a table.
function M.read(dir)
  local text = fs.readFile(dir .. "/" .. FILE)
  if not text then
    return {}
  end
  local chunk, err
  if text:sub(1, 1) == PRECOMPILED then
    err = "precompiled chunk"
  else
    chunk, err = loadstring(text, "=" .. FILE)
  end
  if not chunk then
    return {}, tostring(err)
  end
  local ok, saved = pcall(setfenv(chunk, {}))
  if not ok or type(saved) ~= "table" then
    return {}, ok and "does not return a table" or tostring(saved)
  end
  return saved
end

-- A copy of value Serialize can write, or nil plus false when value itself cannot be saved. Inside a table, an entry
-- whose key or value cannot be saved (a function, userdata, a thread, a non-finite number, a back-reference to a table
-- being copied) is dropped, the way the client drops what it cannot write, and its path is added to skipped. The live
-- table is never touched. stack holds the tables being copied.
local function prune(value, path, stack, skipped)
  local kind = type(value)
  if kind == "string" or kind == "boolean" then
    return value, true
  elseif kind == "number" then
    return value, value == value and value ~= math.huge and value ~= -math.huge
  elseif kind ~= "table" or stack[value] then
    return nil, false
  end
  stack[value] = true
  local copy = {}
  for key, child in pairs(value) do
    local keyed = type(key) == "string" and path .. "." .. key or path .. "[" .. tostring(key) .. "]"
    local kept, ok = nil, false
    if type(key) == "string" or (type(key) == "number" and select(2, prune(key))) then
      kept, ok = prune(child, keyed, stack, skipped)
    end
    if ok then
      copy[key] = kept
    else
      skipped[#skipped + 1] = keyed
    end
  end
  stack[value] = nil
  return copy, true
end

-- Writes saved to dir/saved.lua. What Serialize cannot write is left out (see prune); the paths left out come back
-- sorted, such as "MyDB.callback". The text goes to a temp file first and is renamed over saved.lua, so a write that
-- fails midway leaves the earlier file whole.
function M.write(dir, saved)
  local keep, skipped = {}, {}
  for name, value in pairs(saved) do
    local copy, ok = prune(value, name, {}, skipped)
    if ok then
      keep[name] = copy
    else
      skipped[#skipped + 1] = name
    end
  end
  table.sort(skipped)
  fs.mkdirp(dir)
  local path = dir .. "/" .. FILE
  fs.writeFile(path .. TEMP_SUFFIX, Serialize.dump(keep))
  fs.rename(path .. TEMP_SUFFIX, path)
  return skipped
end

-- Writes the live variables of sess's addon and tells the console what was left out or could not be written. A session
-- without a folder, or whose addon never loaded (a broken TOC, a skipped flavor), writes nothing, so an earlier file
-- survives it.
function M.store(sess)
  local info, dir = sess.s.info, sess.opts.sessionDir
  if not (dir and info and info.status == "loaded") then
    return
  end
  local ok, skipped = pcall(function()
    return M.write(dir, Addon.collectSaved(sess.w, info))
  end)
  if not ok then
    Console.push(sess.w, "system", "saved variables not written: " .. tostring(skipped))
  elseif #skipped > 0 then
    local shown = {}
    for i = 1, math.min(#skipped, MAX_NAMED) do
      shown[i] = skipped[i]
    end
    local more = #skipped > MAX_NAMED and (" and " .. #skipped - MAX_NAMED .. " more") or ""
    Console.push(sess.w, "system", "saved variables left out (they cannot be saved): " .. concat(shown, ", ") .. more)
  end
end

return M
