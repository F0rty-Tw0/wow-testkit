-- Shared by the canaries: logs a canary's fixture addon in through a Scenario and turns the report into findings.
local Scenario = require("scenario")

local M = {}

local TEMPLATE_PREFIX = "template:"

-- Logs in the addon at <dir>/<variant> on flavor; the world is always destroyed. inspect(s) runs after login,
-- before the destroy, and its result is returned beside the report. A skipped addon is a broken canary, so it errors.
function M.login(dir, addon, variant, flavor, inspect)
  local inspected
  local results = Scenario.matrix({ flavor }, function(s)
    s:login()
    if inspect then
      inspected = inspect(s)
    end
  end, { addon = addon, root = dir .. "/" .. variant })
  local report = results[flavor]
  if report.status == "skipped" then
    error(addon .. " (" .. variant .. ") skipped on " .. flavor .. ": " .. tostring(report.reason), 0)
  end
  return report, inspected
end

-- Recorded error messages, optionally only those containing needle (plain text).
function M.errors(report, needle)
  local out = {}
  for _, err in ipairs(report.errors) do
    local message = tostring(err.message)
    if not needle or message:find(needle, 1, true) then
      out[#out + 1] = message
    end
  end
  return out
end

-- Unscripted "template:<Name>" entries.
function M.unscriptedTemplates(report)
  local out = {}
  for _, entry in ipairs(report.unscripted) do
    if entry.name:sub(1, #TEMPLATE_PREFIX) == TEMPLATE_PREFIX then
      out[#out + 1] = entry.name
    end
  end
  return out
end

return M
