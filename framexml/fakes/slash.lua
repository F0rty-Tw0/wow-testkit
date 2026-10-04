-- SlashCmdList and w:slash("/cmd args"): runs the handler an addon registered for a typed slash command.
local M = {}

local Core = require("framexml.fakes.core")

local MAX_ALIASES = 10

-- The SlashCmdList handler with a SLASH_<KEY><n> alias equal to command (lowercase), or nil.
local function handlerFor(command)
  for key, handler in pairs(rawget(_G, "SlashCmdList") or {}) do
    for n = 1, MAX_ALIASES do
      local alias = rawget(_G, "SLASH_" .. tostring(key) .. n)
      if type(alias) == "string" and alias:lower() == command then
        return handler
      end
    end
  end
  return nil
end

-- Calls the matching handler with the text after the command under "addon" context (errors go to the error
-- handler). Returns true when a handler ran, false for an unknown command.
local function slash(self, line)
  local command, args = tostring(line):match("^(%S+)%s*(.-)$")
  local handler = command and handlerFor(command:lower())
  if not handler then
    return false
  end
  self:callAsAddon(handler, args)
  return true
end

function M.install(w)
  w:install("SlashCmdList", {}, Core.GATE)
  w.slash = slash
end

return M
