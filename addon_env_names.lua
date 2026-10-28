-- The base-library names of the per-addon environment (addon_env.lua), kept apart for its 300-line cap.
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

return M
