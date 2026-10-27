-- Taint test helper: a Scenario world with the taint module, addon-owned chunks (chunk name @addon:<Name>/main.lua) and a
-- probe global that reports the running taint. Tests never read a client extract or install.
local AddonEnv = require("addon_env")
local Scenario = require("scenario")

local M = {}

-- Runs fn(w, Taint, s) on a fresh Scenario world, always destroyed.
function M.withTaint(flavor, fn)
  local s = Scenario.new({ addon = "T", root = "T", flavor = flavor })
  local Taint = require("taint")
  local ok, err = pcall(fn, s.w, Taint, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

-- src compiled as addon's main.lua in a fresh addon environment, so the taint model counts it as that addon's code.
function M.chunk(w, addon, src)
  local fn = assert(loadstring(src, "@addon:" .. addon .. "/main.lua"))
  return setfenv(fn, AddonEnv.newEnv(w))
end

-- Runs src as addon's code through w:callAsAddon; returns the packed results ({ n, ok, ... }).
function M.run(w, addon, src, ...)
  return w:callAsAddon(M.chunk(w, addon, src), ...)
end

-- Installs the global TK_Seen(), which returns the running taint.
function M.probe(w, Taint)
  w:setGlobal("TK_Seen", function()
    return Taint.current(w)
  end)
end

return M
