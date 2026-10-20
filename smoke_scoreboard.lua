-- Smoke scoreboard text: one row per addon with a cell per flavor, then the most common first errors and
-- unscripted names, then totals.
local M = {}

local COLUMN_GAP = 2
local RANK_LIMIT = 10

-- "PASS (<n>u)", "FAIL <errors> (<n>u)" or "SKIP"; n = distinct unscripted names the run reported.
local function cell(report)
  if report.status == "skipped" then
    return "SKIP"
  end
  local suffix = " (" .. #report.unscripted .. "u)"
  if report.status == "pass" then
    return "PASS" .. suffix
  end
  return "FAIL " .. #report.errors .. suffix
end

-- Columns pad to their widest text (header included) plus two spaces; trailing spaces are dropped.
local function tableLines(rows, flavors)
  local header = { "addon" }
  for i, flavor in ipairs(flavors) do
    header[i + 1] = flavor
  end
  local grid = { header }
  for _, row in ipairs(rows) do
    local line = { row.name }
    for i, flavor in ipairs(flavors) do
      line[i + 1] = cell(row.results[flavor])
    end
    grid[#grid + 1] = line
  end
  local widths = {}
  for _, line in ipairs(grid) do
    for i, text in ipairs(line) do
      widths[i] = math.max(widths[i] or 0, #text + COLUMN_GAP)
    end
  end
  local lines = {}
  for r, line in ipairs(grid) do
    local padded = {}
    for i, text in ipairs(line) do
      padded[i] = text .. string.rep(" ", widths[i] - #text)
    end
    lines[r] = (table.concat(padded):gsub("%s+$", ""))
  end
  return lines
end

-- The RANK_LIMIT largest counts, by count descending, then key ascending (byte order).
local function ranked(counts)
  local list = {}
  for key, count in pairs(counts) do
    list[#list + 1] = { key = key, count = count }
  end
  table.sort(list, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.key < b.key
  end)
  for i = #list, RANK_LIMIT + 1, -1 do
    list[i] = nil
  end
  return list
end

-- Visits every requested run's report as fn(report).
local function eachRun(rows, flavors, fn)
  for _, row in ipairs(rows) do
    for _, flavor in ipairs(flavors) do
      fn(row.results[flavor])
    end
  end
end

local function bucketLines(rows, flavors)
  local firstErrors, unscripted = {}, {}
  local totals = { pass = 0, fail = 0, skipped = 0 }
  eachRun(rows, flavors, function(report)
    totals[report.status] = totals[report.status] + 1
    if report.status == "fail" then
      local message = tostring(report.errors[1].message)
      firstErrors[message] = (firstErrors[message] or 0) + 1
    end
    for _, entry in ipairs(report.unscripted) do
      unscripted[entry.name] = (unscripted[entry.name] or 0) + 1
    end
  end)
  local lines = { "first errors (runs):" }
  for _, group in ipairs(ranked(firstErrors)) do
    lines[#lines + 1] = "  " .. group.count .. "  " .. group.key
  end
  lines[#lines + 1] = "unscripted (runs):"
  local names = {}
  for i, entry in ipairs(ranked(unscripted)) do
    names[i] = entry.key .. " x" .. entry.count
  end
  if #names > 0 then
    lines[#lines + 1] = "  " .. table.concat(names, ", ")
  end
  local runs = totals.pass + totals.fail + totals.skipped
  local format = "%d addons, %d runs: %d pass, %d fail, %d skipped"
  lines[#lines + 1] = string.format(format, #rows, runs, totals.pass, totals.fail, totals.skipped)
  return lines
end

-- The scoreboard for runAddon results (any order): rows sorted by addon name, then the first-error and unscripted
-- buckets, then totals.
function M.format(results, flavors)
  local rows = {}
  for i, result in ipairs(results) do
    rows[i] = result
  end
  table.sort(rows, function(a, b)
    return a.name < b.name
  end)
  local lines = tableLines(rows, flavors)
  for _, line in ipairs(bucketLines(rows, flavors)) do
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
