-- The base-library names of the per-addon environment (addon_env.lua), kept apart for its 300-line cap.
local Taint = require("taint")

local M = {}

local hostRawget = rawget

-- The Lua 5.1 base functions and libraries kit Lua reads bare: an addon write to one stays in the view, never in _G.
local KEPT_NAMES = "assert collectgarbage error gcinfo getfenv getmetatable ipairs loadstring newproxy next pairs pcall"
  .. " rawequal rawget rawset select setfenv setmetatable tonumber tostring type unpack xpcall string table math os coroutine bit"
M.KEPT = {}
for name in KEPT_NAMES:gmatch("%S+") do
  M.KEPT[name] = true
end

-- Stores an addon write to a KEPT name as the view's override; nil or false hides the name (addon_env.lua's hidden
-- compares _G with hostValues), so the view answers nil while _G keeps the host value for kit code.
function M.keep(overrides, hostValues, key, value)
  overrides[key] = value or false
  if not value then
    hostValues[key] = hostRawget(_G, key)
  end
end

-- An addon write to a KEPT name: kept in the view, and _G's slot tainted as the write there would have (Taint.rawset),
-- so issecurevariable and the taint log see it although _G still holds the host value.
function M.write(w, overrides, hostValues, key, value)
  local held = overrides[key]
  if held == nil then
    held = hostRawget(_G, key)
  end
  M.keep(overrides, hostValues, key, value)
  if w.taint then
    Taint.attribute(w, _G, key, held ~= nil and held ~= false, Taint.current(w))
  end
end

return M
