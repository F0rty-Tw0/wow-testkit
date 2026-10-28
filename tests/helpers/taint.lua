-- Taint test helper: a Scenario world with the taint module, addon-owned chunks (chunk name @addon:<Name>/main.lua) and a
-- probe global that reports the running taint. Tests never read a client extract or install.
local AddonEnv = require("addon_env")
local Scenario = require("scenario")

local M = {}

-- Runs fn(w, Taint, s) on a fresh Scenario world, always destroyed. opts overrides the Scenario.new options (addon, root).
function M.withTaint(flavor, fn, opts)
  local options = { addon = "T", root = "T", flavor = flavor }
  for key, value in pairs(opts or {}) do
    options[key] = value
  end
  local s = Scenario.new(options)
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

-- Puts the world in combat lockdown (on) or out of it (off): the mock's combat flag, the source of InCombatLockdown.
function M.setCombat(w, on)
  w:setMock({ combat = on })
end

-- The log entries of kind (every entry when kind is nil), oldest first.
function M.events(w, kind)
  local out = {}
  for _, entry in ipairs(w.taint.log) do
    if kind == nil or entry.kind == kind then
      out[#out + 1] = entry
    end
  end
  return out
end

return M
