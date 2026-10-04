-- Canary harness: every canaries/<layer>/<name>/canary.lua plants a known bug (bug/) beside its fix (fixed/)
-- and proves a kit check flags the bug and stays quiet on the fix.
--   require("canaries.run")                       -> module (discover, evaluate, main)
--   python tools/run51.py --script canaries/run.lua [layer] -> runs the canaries, returns the exit code
local fs = require("fs")

local M = {}

local DEFAULT_FLAVORS = { "retail" }
local KNOWN_MISS_FLAGGED = "known-miss now flagged — update ceiling"

local isModule = (...) == "canaries.run"

local function subdirs(dir)
  local names = {}
  for _, name in ipairs(fs.list(dir)) do
    if fs.isdir(dir .. "/" .. name) then
      names[#names + 1] = name
    end
  end
  return names
end

-- Loads each canary.lua with its own directory as the first vararg.
function M.discover(root)
  local canaries = {}
  for _, layer in ipairs(subdirs(root)) do
    for _, name in ipairs(subdirs(root .. "/" .. layer)) do
      local dir = root .. "/" .. layer .. "/" .. name
      if fs.exists(dir .. "/canary.lua") then
        canaries[#canaries + 1] = assert(loadfile(dir .. "/canary.lua"))(dir)
      end
    end
  end
  return canaries
end

-- Findings list, or nil plus a failure reason.
local function runCheck(canary, variant, flavor)
  local ok, findings = pcall(canary.check, variant, flavor)
  if not ok then
    return nil, "check errored: " .. tostring(findings)
  end
  if type(findings) ~= "table" then
    return nil, "check errored: returned " .. type(findings) .. ", expected a list of findings"
  end
  return findings
end

-- pass, reason
local function judge(canary, flavor)
  local bug, bugErr = runCheck(canary, "bug", flavor)
  if not bug then
    return false, bugErr
  end
  if canary.knownMiss then
    return #bug == 0, #bug > 0 and KNOWN_MISS_FLAGGED or nil
  end
  if #bug == 0 then
    return false, "bug not flagged"
  end
  local fixed, fixedErr = runCheck(canary, "fixed", flavor)
  if not fixed then
    return false, fixedErr
  end
  if #fixed > 0 then
    return false, "fixed flagged: " .. tostring(fixed[1])
  end
  return true
end

function M.evaluate(canary)
  local results = {}
  for _, flavor in ipairs(canary.flavors or DEFAULT_FLAVORS) do
    local pass, reason = judge(canary, flavor)
    results[#results + 1] = {
      name = canary.name,
      layer = canary.layer,
      flavor = flavor,
      pass = pass,
      reason = reason,
      knownMiss = canary.knownMiss or nil,
    }
  end
  return results
end

local function report(result, totals)
  local id = result.layer .. "/" .. result.name .. " " .. result.flavor
  if not result.pass then
    totals.fail = totals.fail + 1
    print("CANARY FAIL " .. id .. ": " .. result.reason)
  elseif result.knownMiss then
    totals.knownMiss = totals.knownMiss + 1
    print("KNOWN-MISS " .. id)
  else
    totals.pass = totals.pass + 1
    print("CANARY PASS " .. id)
  end
end

-- Runs every canary under root (optionally one layer); returns 0 when all pass, else 1.
function M.main(root, layerFilter)
  local totals = { pass = 0, fail = 0, knownMiss = 0 }
  for _, canary in ipairs(M.discover(root)) do
    if not layerFilter or canary.layer == layerFilter then
      for _, result in ipairs(M.evaluate(canary)) do
        report(result, totals)
      end
    end
  end
  local ran = totals.pass + totals.fail + totals.knownMiss
  print(string.format("CANARIES %d passed, %d failed, %d known-miss", totals.pass, totals.fail, totals.knownMiss))
  if ran == 0 then
    print("CANARY FAIL no canaries found" .. (layerFilter and (" for layer " .. layerFilter) or ""))
    return 1
  end
  return totals.fail > 0 and 1 or 0
end

if isModule then
  return M
end

local SELF_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
return M.main(SELF_DIR, ...)
