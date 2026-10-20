-- Scenarios: one addon logged into one flavor's world, driven the way the client drives it (login events, mouseover
-- hover, events, time, slash commands) and summarized as a per-flavor report. Scenario.matrix runs a scenario on
-- several flavors and always destroys each world; Scenario.runFile does that for a scn_<name>.lua file.
local M = {}

local Addon = require("addon")
local Flavors = require("tools.flavors")
local FrameXML = require("framexml.fakes")
local Golden = require("golden")
local Input = require("input")
local Snapshot = require("snapshot")
local Units = require("units")
local Widgets = require("ui.widgets")
local World = require("world")

local MOUSEOVER = "mouseover"
local ENGINE = "blizzard"
local LOGIN_EVENTS = { "VARIABLES_LOADED", "PLAYER_LOGIN" }
-- PLAYER_ENTERING_WORLD payload: isInitialLogin, isReloadingUi.
local INITIAL_LOGIN, RELOADING_UI = true, false
-- ADDON_LOADED payload: addOnName, containsBindings (the manifest lists both as required).
local CONTAINS_BINDINGS = false

local Scenario = {}
Scenario.__index = Scenario
require("scenario_input").extend(Scenario)

-- Raised by s:login when the addon is skipped on the flavor: it ends the run, and the matrix reports the flavor
-- as skipped instead of failed.
local SKIPPED = setmetatable({}, {
  __tostring = function()
    return "addon skipped on this flavor; the scenario stops at s:login"
  end,
})

local function copyList(list)
  local out = {}
  for i, v in ipairs(list or {}) do
    out[i] = v
  end
  return out
end

local function installWorld(w)
  Units.install(w)
  Widgets.install(w)
  FrameXML.installStage1(w)
end

-- opts: { addon, root, flavor, saved, config, golden? = { root, scenario, update } }. s.ns / s.info exist only
-- after s:login. With golden, s:snapshot checks goldens under golden.root and the world runs in golden mode.
function M.new(opts)
  local w = World.new({ flavor = opts.flavor })
  local ok, err = pcall(installWorld, w)
  if not ok then
    w:destroy()
    error(err, 0)
  end
  local golden = opts.golden or {}
  w.goldenMode = opts.golden ~= nil
  return setmetatable({
    w = w,
    flavor = w.flavor,
    addon = opts.addon,
    root = opts.root,
    saved = opts.saved,
    config = opts.config,
    goldenRoot = golden.root,
    scenarioName = golden.scenario,
    update = golden.update,
    notes = {},
  }, Scenario)
end

function Scenario:note(text)
  self.notes[#self.notes + 1] = text
end

-- Fires event under engine context when the flavor has it; otherwise records a note.
function Scenario:fireIfKnown(event, ...)
  local w = self.w
  if not (w.manifest.events[event] or w.globals.events[event]) then
    self:note(event .. " does not exist on " .. self.flavor .. "; not fired")
    return
  end
  w:run(ENGINE, w.fire, w, event, ...)
end

-- Loads the addon, applies saved variables and fires the login events. opts.saved overrides s.saved. When the
-- addon is skipped on the flavor (not declared), raises SKIPPED so the rest of the run does not execute.
function Scenario:login(opts)
  if opts and opts.saved ~= nil then
    self.saved = opts.saved
  end
  local w = self.w
  self.ns, self.info = w:run(ENGINE, Addon.load, w, { name = self.addon, root = self.root })
  if self.info.status == "skipped" then
    error(SKIPPED, 0)
  end
  Addon.applySaved(w, self.info, self.saved)
  self:fireIfKnown("ADDON_LOADED", self.addon, CONTAINS_BINDINGS)
  for _, event in ipairs(LOGIN_EVENTS) do
    self:fireIfKnown(event)
  end
  self:fireIfKnown("PLAYER_ENTERING_WORLD", INITIAL_LOGIN, RELOADING_UI)
end

function Scenario:unit(token, data)
  self.w:unit(token, data)
end

-- (I10) The mouse moves off any frame (it gets OnLeave) and over the world; WorldFrame holds the focus only when
-- its motion is enabled.
local function moveMouseToWorld(w)
  local focus = w.input.mouseFocus
  if focus and focus ~= _G.WorldFrame then
    Input.leave(w, focus)
  end
  w.input.mouseFocus = _G.WorldFrame:IsMouseMotionEnabled() and _G.WorldFrame or nil
end

-- Points mouseover at unit (a unit without a fixture gets an empty one, answering defaults), then shows the unit
-- tooltip the way the client does on UPDATE_MOUSEOVER_UNIT.
function Scenario:hover(unit)
  local w = self.w
  w:run(ENGINE, moveMouseToWorld, w)
  if not w.unitState.byToken[unit:lower()] then
    self:note("hover: no fixture for '" .. unit .. "'; using defaults")
    w:unit(unit, {})
  end
  w:mouseover(unit:lower() ~= MOUSEOVER and unit or nil)
  self:fireIfKnown("UPDATE_MOUSEOVER_UNIT")
  w:run(ENGINE, function()
    _G.GameTooltip_SetDefaultAnchor(_G.GameTooltip, _G.UIParent)
    _G.GameTooltip:SetUnit(MOUSEOVER)
    _G.GameTooltip:Show()
  end)
end

function Scenario:fire(event, ...)
  local w = self.w
  w:run(ENGINE, w.fire, w, event, ...)
end

function Scenario:advance(seconds)
  local w = self.w
  w:run(ENGINE, w.advance, w, seconds)
end

function Scenario:slash(text)
  local w = self.w
  return w:run(ENGINE, w.slash, w, text)
end

local function snapshotText(target)
  if target.kind == "menu" then
    return Snapshot.menu(target)
  end
  if target:GetObjectType() == "GameTooltip" then
    return Snapshot.tooltip(target)
  end
  return Snapshot.frame(target)
end

-- Checks target's snapshot against the golden file "<name>.<flavor>.txt". A mismatch is recorded as an error
-- (failing the report) instead of thrown; a newly written golden adds a note. The snapshot's own widget reads
-- are not counted as unscripted.
function Scenario:snapshot(name, target)
  local w = self.w
  if not self.goldenRoot then
    error("s:snapshot needs a golden root; run the scenario through Scenario.runFile", 2)
  end
  local unscripted = {}
  for key, count in pairs(w.unscripted) do
    unscripted[key] = count
  end
  local text = snapshotText(target)
  w.unscripted = unscripted
  local ok, result = pcall(Golden.check, self.goldenRoot, self.scenarioName, name, self.flavor, text, self.update)
  if not ok then
    w:recordError(result)
  elseif result == "written" then
    self:note("golden written: " .. self.scenarioName .. "/" .. name .. "." .. self.flavor .. ".txt")
  end
end

local function unscriptedList(unscripted)
  local list = {}
  for name, count in pairs(unscripted) do
    list[#list + 1] = { name = name, count = count }
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

-- status: "skipped" when the addon was skipped (reason says why), else "fail" when any error was recorded, else
-- "pass".
function Scenario:report()
  local w, info = self.w, self.info
  local status = "pass"
  if info and info.status == "skipped" then
    status = "skipped"
  elseif #w.errors > 0 then
    status = "fail"
  end
  local notes = copyList(info and info.report)
  for _, text in ipairs(self.notes) do
    notes[#notes + 1] = text
  end
  for _, text in ipairs(w.notes or {}) do
    notes[#notes + 1] = text
  end
  return {
    flavor = self.flavor,
    status = status,
    reason = info and info.reason,
    errors = copyList(w.errors),
    unscripted = unscriptedList(w.unscripted),
    warnings = copyList(w.warnings),
    notes = notes,
  }
end

local function failedReport(flavor, message, traceback)
  local errors = { { message = message, traceback = traceback } }
  return { flavor = flavor, status = "fail", errors = errors, unscripted = {}, warnings = {}, notes = {} }
end

-- Calls fn(s); returns ok, err, traceback (taken at the error, before the stack unwinds).
local function guarded(fn, s)
  local traceback
  local ok, err = xpcall(function()
    fn(s)
  end, function(e)
    traceback = debug.traceback()
    return e
  end)
  return ok, err, traceback
end

-- One flavor: a thrown error from fn is recorded in the world (so it fails the report), except SKIPPED; the world
-- is always destroyed.
local function runFlavor(flavor, fn, opts)
  local newOpts = { addon = opts.addon, root = opts.root, flavor = flavor, saved = opts.saved, config = opts.config, golden = opts.golden }
  local okNew, s = pcall(M.new, newOpts)
  if not okNew then
    return failedReport(flavor, s, nil)
  end
  local ok, err, traceback = s.w:run("scenario", guarded, fn, s)
  if not ok and err ~= SKIPPED then
    s.w:recordError(err, traceback)
  end
  local okReport, report = pcall(s.report, s)
  s.w:destroy()
  if not okReport then
    return failedReport(flavor, report, nil)
  end
  return report
end

-- Runs fn(s) on each flavor with a fresh scenario built from opts { addon, root, saved, config, golden }.
-- Returns { [flavor] = report }.
function M.matrix(flavors, fn, opts)
  local results = {}
  for _, flavor in ipairs(flavors) do
    results[flavor] = runFlavor(flavor, fn, opts or {})
  end
  return results
end

local function scenarioName(path)
  local file = path:gsub("\\", "/"):match("([^/]+)$")
  return (file:gsub("^scn_", ""):gsub("%.lua$", ""))
end

-- path: a file returning { run = function(s) end, flavors?, saved?, config? }; opts: { addon, root, flavors?,
-- update? }. Snapshots check goldens under the addon root. Returns { name, results = { [flavor] = report } }.
function M.runFile(path, opts)
  local file = assert(loadfile(path))()
  if type(file) ~= "table" or type(file.run) ~= "function" then
    error("scenario file " .. path .. " must return a table with a run function", 2)
  end
  local flavors = opts.flavors or file.flavors or Flavors.list
  local name = scenarioName(path)
  local golden = { root = opts.root, scenario = name, update = opts.update }
  local matrixOpts = { addon = opts.addon, root = opts.root, saved = file.saved, config = file.config, golden = golden }
  return { name = name, results = M.matrix(flavors, file.run, matrixOpts) }
end

return M
