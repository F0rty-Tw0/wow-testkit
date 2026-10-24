-- Preview: `tk preview`. Runs one addon through a scenario on one flavor, writes the render snapshot to <out>/snapshot.json
-- (before any error is reported), then runs tools/preview.py to resolve the snapshot's art and, with a png path, to
-- shoot it with headless Chrome. Exit 0 clean; 1 when the addon or scenario recorded an error or a step failed; 2 on
-- a usage error, an unreadable scenario or an addon skipped on the flavor.
local M = {}

local Flavors = require("tools.flavors")
local Home = require("home")
local Proc = require("proc")
local Scenario = require("scenario")
local ScenarioPreview = require("scenario_preview")
local Toc = require("toc")
local fs = require("fs")

local EXIT_OK, EXIT_FAIL, EXIT_USAGE = 0, 1, 2
local DEFAULT_FLAVOR = "retail"
local DEFAULT_SIZE = { width = 1920, height = 1080 }
local ERRORS_SHOWN = 10
local SNAPSHOT_FILE = "/snapshot.json"
local STEP_LOG = "/.step.log"
-- Every kit module loads from the same package.path root as this file.
local KIT_ROOT = debug.getinfo(1, "S").source:match("^@(.*)[/\\]preview%.lua$") or "."

-- Runs argv, logging its output to logPath; returns its exit code. Tests replace this field.
M.exec = Proc.run

local function defaultScenario(s)
  s:login()
end

-- The scenario file's table, or nil plus a message. A scenario file is host code, like Scenario.runFile's.
local function loadScenario(path)
  if not path then
    return { run = defaultScenario }
  end
  local chunk, err = loadfile(path)
  if not chunk then
    return nil, "cannot read scenario " .. path .. ": " .. tostring(err)
  end
  local ok, file = pcall(chunk)
  if not ok or type(file) ~= "table" or type(file.run) ~= "function" then
    return nil, "scenario " .. path .. " must return a table with a run function"
  end
  return file
end

local DEVICE_NAMES = { CON = true, PRN = true, AUX = true, NUL = true }

-- True when windows would open name as a device: CON, PRN, AUX, NUL, COM0-9 or LPT0-9, with or without an extension.
local function isDeviceName(name)
  local stem = name:match("^[^.]*"):upper()
  return DEVICE_NAMES[stem] or stem:find("^COM%d$") or stem:find("^LPT%d$")
end

-- The default output folder name for an addon: every character outside [%w_.-] becomes "_", so an addon named
-- "!Foo" or "$(cmd)" can neither trip the shell nor escape the preview folder. A windows device name gets a leading
-- "_" and a trailing dot (which windows drops) becomes "_", so the folder is the same on every OS. Nil when only dots
-- (or nothing) are left.
local function folderName(addon)
  local name = addon:gsub("[^%w_.%-]", "_")
  if name:find("^%.*$") then
    return nil
  end
  name = name:gsub("%.+$", function(dots)
    return ("_"):rep(#dots)
  end)
  return isDeviceName(name) and "_" .. name or name
end

-- The default output folder for addon, or nil plus a message.
local function defaultOut(addon)
  local folder = folderName(addon)
  if not folder then
    return nil, "cannot name the output folder after the addon '" .. addon .. "': pass --out"
  end
  return Home.path("preview", folder)
end

-- { name, flavor, file, out, size, matrixOpts } for opts, or nil plus a message.
local function context(opts)
  local root = opts.addonDir
  if not (root and fs.isdir(root)) then
    return nil, "no such directory: " .. tostring(root)
  end
  local name, nameErr = Toc.addonName(root)
  if not name then
    return nil, nameErr
  end
  local flavor = opts.flavor or DEFAULT_FLAVOR
  local flavorOk, flavorErr = pcall(Flavors.get, flavor)
  if not flavorOk then
    return nil, flavorErr
  end
  local file, scenarioErr = loadScenario(opts.scenario)
  if not file then
    return nil, scenarioErr
  end
  local size = opts.size or DEFAULT_SIZE
  local out, outErr = opts.out, nil
  if not out then
    out, outErr = defaultOut(name)
  end
  if not out then
    return nil, outErr
  end
  local matrixOpts = { addon = name, root = root, screen = size, preview = { out = out }, saved = file.saved, config = file.config }
  return { flavor = flavor, file = file, out = out, size = size, png = opts.png, matrixOpts = matrixOpts }
end

-- The scenario function: runs the scenario, writes the final snapshot whatever happened, then rethrows the scenario's
-- error unchanged (so Scenario's SKIPPED sentinel keeps its identity). state gets the previews and whether the final
-- snapshot was written.
local function scenarioFn(ctx, state)
  return function(s)
    local ran, runErr = pcall(ctx.file.run, s)
    state.previews = s.previews
    local wrote, writeErr = pcall(ScenarioPreview.write, s, ctx.out)
    state.wrote = wrote
    if not ran then
      error(runErr, 0)
    elseif not wrote then
      error(writeErr, 0)
    end
  end
end

local function firstLine(message)
  return (tostring(message):match("[^\r\n]*"))
end

local function writeErrors(report, write)
  for i = 1, math.min(#report.errors, ERRORS_SHOWN) do
    write("error: " .. firstLine(report.errors[i].message) .. "\n")
  end
  if #report.errors > ERRORS_SHOWN then
    write("error: " .. (#report.errors - ERRORS_SHOWN) .. " more not shown\n")
  end
end

local function pythonStep(label, ...)
  return { label = label, argv = { os.getenv("TK_PYTHON") or "python", KIT_ROOT .. "/tools/preview.py", label, ... } }
end

-- resolve for the final snapshot and each s:preview dir, then png.
local function stepsFor(ctx, previews)
  local steps = { pythonStep("resolve", ctx.out .. SNAPSHOT_FILE, ctx.out) }
  for _, dir in ipairs(previews or {}) do
    steps[#steps + 1] = pythonStep("resolve", dir .. SNAPSHOT_FILE, dir)
  end
  if ctx.png then
    local size = ctx.size.width .. "x" .. ctx.size.height
    steps[#steps + 1] = pythonStep("png", ctx.out, ctx.png, "--size", size)
    steps[#steps].done = "preview: wrote " .. ctx.png
  end
  return steps
end

local function logText(path)
  local text = (fs.readFile(path) or ""):gsub("\r", "")
  return (text ~= "" and not text:find("\n$")) and text .. "\n" or text
end

-- Runs one step; its log is echoed. Returns false (after saying why) when it failed or raised.
local function runStep(step, logPath, write)
  fs.writeFile(logPath, "")
  local ran, code = pcall(M.exec, step.argv, logPath)
  local failure = not ran and "failed: " .. tostring(code) or code ~= 0 and "failed (exit " .. tostring(code) .. ")"
  if failure then
    write("preview: " .. step.label .. " " .. failure .. "\n")
  end
  write(logText(logPath))
  if not failure and step.done then
    write(step.done .. "\n")
  end
  return not failure
end

local function runSteps(steps, out, write)
  for _, step in ipairs(steps) do
    if not runStep(step, out .. STEP_LOG, write) then
      return false
    end
  end
  return true
end

-- A run that fails must not leave the previous run's snapshot or picture behind to be read as this run's.
local function clearStale(ctx)
  os.remove(ctx.out .. SNAPSHOT_FILE)
  if ctx.png then
    os.remove(ctx.png)
  end
end

-- opts: { addonDir, flavor?, scenario?, size? = { width, height }, out?, png? }; all output goes through write.
function M.run(opts, write)
  local ctx, message = context(opts)
  if not ctx then
    write("preview: " .. message .. "\n")
    return EXIT_USAGE
  end
  local made, makeErr = pcall(fs.mkdirp, ctx.out)
  if not made then
    write("preview: " .. tostring(makeErr) .. "\n")
    return EXIT_USAGE
  end
  clearStale(ctx)
  local state = {}
  local report = Scenario.matrix({ ctx.flavor }, scenarioFn(ctx, state), ctx.matrixOpts)[ctx.flavor]
  if report.status == "skipped" then
    write("preview: addon skipped on " .. ctx.flavor .. ": " .. tostring(report.reason) .. "\n")
    return EXIT_USAGE
  end
  if state.wrote then
    write("preview: wrote " .. ctx.out .. SNAPSHOT_FILE .. "\n")
  end
  writeErrors(report, write)
  local stepsOk = state.wrote and runSteps(stepsFor(ctx, state.previews), ctx.out, write)
  return (report.status == "pass" and stepsOk) and EXIT_OK or EXIT_FAIL
end

return M
