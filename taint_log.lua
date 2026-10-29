-- The taint log (w.taint.log): recording entries (taint.lua re-exports record, listen and who) and reading it as plain
-- data, for snapshots and the scenario step.
local M = {}

-- Localized: addon code may assign globals of the same names.
local pairs, ipairs, type, tostring, tremove = pairs, ipairs, type, tostring, table.remove

M.LOG_LIMIT = 1000

-- The name log text gives a taint: the addon's, or "a macro" for macro taint (the empty string).
function M.who(taint)
  return taint == "" and "a macro" or taint
end

-- Appends entry to the log (seq and time filled in, the oldest dropped past LOG_LIMIT) and passes it to each listener.
function M.record(w, entry)
  local t = w.taint
  t.seq = t.seq + 1
  entry.seq, entry.time = t.seq, w.now
  local log = t.log
  log[#log + 1] = entry
  if #log > M.LOG_LIMIT then
    tremove(log, 1)
  end
  for _, listener in ipairs(t.listeners) do
    listener(entry)
  end
  return entry
end

-- Calls fn(entry) with each entry logged from now on.
function M.listen(w, fn)
  local listeners = w.taint.listeners
  listeners[#listeners + 1] = fn
end

-- A copy of the log, oldest first, each entry copied one level; a name that is not a string or number (a table key) is
-- given as its tostring, so the copy is plain data.
function M.copyLog(w)
  local out = {}
  for i, entry in ipairs(w.taint.log) do
    local copy = {}
    for key, value in pairs(entry) do
      copy[key] = value
    end
    local name = copy.name
    if name ~= nil and type(name) ~= "string" and type(name) ~= "number" then
      copy.name = tostring(name)
    end
    out[i] = copy
  end
  return out
end

return M
