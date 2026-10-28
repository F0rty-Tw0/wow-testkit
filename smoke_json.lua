-- Smoke scoreboard as JSON: the document `tk smoke --json` prints, one object per addon with a run per flavor, for
-- diffing two runs. Keys are sorted by Json.encode, so the text is stable.
local M = {}

local Json = require("json")

local VERSION = 1
local INDENT = 2

local function runEntry(report)
  local errors = {}
  for i, err in ipairs(report.errors) do
    errors[i] = { message = tostring(err.message) }
  end
  local unscripted = {}
  for i, entry in ipairs(report.unscripted) do
    unscripted[i] = { name = entry.name, count = entry.count }
  end
  table.sort(unscripted, function(a, b)
    return a.name < b.name
  end)
  return {
    status = report.status,
    reason = report.reason,
    errors = errors,
    printed = report.printed or 0,
    unscripted = unscripted,
  }
end

-- The document for runAddon results (any order) and the requested flavors: { ver, flavors, addons, totals }.
function M.document(results, flavors)
  local rows = {}
  for i, result in ipairs(results) do
    rows[i] = result
  end
  table.sort(rows, function(a, b)
    return a.name < b.name
  end)
  local totals = { addons = #rows, runs = #rows * #flavors, pass = 0, fail = 0, skipped = 0 }
  local addons = {}
  for i, row in ipairs(rows) do
    local runs = {}
    for _, flavor in ipairs(flavors) do
      local report = row.results[flavor]
      totals[report.status] = totals[report.status] + 1
      runs[flavor] = runEntry(report)
    end
    addons[i] = { name = row.name, runs = runs }
  end
  return { ver = VERSION, flavors = flavors, addons = addons, totals = totals }
end

-- The document as JSON text, ending in a newline.
function M.format(results, flavors)
  return Json.encode(M.document(results, flavors), INDENT) .. "\n"
end

return M
