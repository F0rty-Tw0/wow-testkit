-- The scenario's login load step: the addon and its dependencies load in dependency order, each followed by its saved
-- variables and ADDON_LOADED before the next addon's files run.
local M = {}

local Addon = require("addon")
local AddonDeps = require("addon_deps")

local ENGINE = "blizzard"
-- ADDON_LOADED payload: addOnName, containsBindings (the manifest lists both as required).
local CONTAINS_BINDINGS = false

-- w.mock.addonsDir for a new scenario: opts.addonsDir, else the parent of the addon's folder.
function M.dirOf(opts)
  return opts.addonsDir or (opts.root and AddonDeps.addonsDirOf(opts.root)) or nil
end

-- Loads s.addon and its dependencies (AddonDeps.loadAll under the engine context). Sets s.deps to the dependency
-- entries ({ name, ns, info }, in load order) and notes each as loaded. Returns the addon's ns, info; a skipped info
-- means nothing of the addon ran.
function M.load(s)
  local w = s.w
  local opts = { name = s.addon, root = s.root, addonsDir = w.mock.addonsDir }
  local entries = w:run(ENGINE, AddonDeps.loadAll, w, opts, function(entry)
    Addon.applySaved(w, entry.info, entry.name == s.addon and s.saved or nil)
    s:fireIfKnown("ADDON_LOADED", entry.name, CONTAINS_BINDINGS)
  end)
  local last = table.remove(entries)
  s.deps = entries
  for _, entry in ipairs(entries) do
    s:note("loaded dependency " .. entry.name)
  end
  return last.ns, last.info
end

return M
