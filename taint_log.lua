-- Reading the taint log (taint.lua records it in w.taint.log) as plain data, for snapshots and the scenario step.
local M = {}

-- Localized: addon code may assign globals of the same names.
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring

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
