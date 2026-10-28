-- State drivers and unit watches: RegisterStateDriver and its siblings re-evaluate a frame's macro conditional on a 0.2 s
-- throttle of world time and set the attribute (state-<state>) when the result changes; a unit watch shows or hides a frame
-- by whether its unit exists. One lazily created timer on the world clock is the manager's OnUpdate: it exists only while a
-- driver or watch does, and a listed event brings the next update forward to the next advance.
-- source: extract retail 70575 blizzard_restrictedaddonenvironment/securestatedriver.lua (throttle :63, parse call :96,
-- resolveDriver :95-117, unit watch :69-88), row TS16; the code is the kit's.
-- Deviations: the manager's `updatetime` attribute is not modelled (the throttle is fixed), and a unit exists when
-- UnitExists says so (the extract also accepts UnitIsVisible; a kit unit with no fixture does not exist).
local MacroCond = require("macro_cond")
local SecureAttributes = require("secure_attributes")
local Taint = require("taint")

local M = {}

-- Localized: addon code may assign globals of the same names.
local type, next, pairs, ipairs, tonumber = type, next, pairs, ipairs, tonumber

local FRAMEXML = { gate = "framexml", flavors = {} }
local UPDATE_THROTTLE = 0.2

local RESET_EVENTS = {}
for event in
  ([[MODIFIER_STATE_CHANGED ACTIONBAR_PAGE_CHANGED UPDATE_BONUS_ACTIONBAR PLAYER_ENTERING_WORLD UPDATE_SHAPESHIFT_FORM
  UPDATE_STEALTH PLAYER_TARGET_CHANGED PLAYER_FOCUS_CHANGED PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED UNIT_PET
  GROUP_ROSTER_UPDATE]]):gmatch("%S+")
do
  RESET_EVENTS[event] = true
end

-- Runs fn(...) as secure kit code: the manager is secure, whoever registered the frame.
local function secure(w, fn, ...)
  return w:run("blizzard", Taint.secure, w, fn, ...)
end

local function timerPending(w, timer)
  for _, pending in ipairs(w.timers) do
    if pending == timer then
      return true
    end
  end

  return false
end

local function wanted(state)
  return next(state.attrs) ~= nil or next(state.watchers) ~= nil
end

local function resolveDriver(w, frame, attribute, values)
  local result = MacroCond.eval(w, values)
  if attribute == "state-visibility" then
    if result == "show" then
      frame:Show()
      frame:SetAttribute("statehidden", nil)
    elseif result == "hide" then
      frame:Hide()
      frame:SetAttribute("statehidden", true)
    end

    return
  end
  if result == nil then
    return
  end
  local value = nil
  if result ~= "nil" then
    value = tonumber(result) or result
  end
  if value ~= frame:GetAttribute(attribute) then
    frame:SetAttribute(attribute, value)
  end
end

-- UnitExists per unit, remembered for one update pass; the global is read through Taint.read (row TS4, assumed).
local function unitExists(w, cache, unit)
  if cache[unit] == nil then
    Taint.read(w, _G, "UnitExists")
    cache[unit] = _G.UnitExists(unit) == true
  end

  return cache[unit]
end

local function updateWatch(w, frame, asState, cache)
  local unit = SecureAttributes.unitOf(w, frame)
  local present = unit ~= nil and unitExists(w, cache, unit)
  if asState then
    if frame:GetAttribute("state-unitexists") ~= present then
      frame:SetAttribute("state-unitexists", present)
    end
  elseif present then
    frame:Show()
    frame:SetAttribute("statehidden", nil)
  else
    frame:Hide()
    frame:SetAttribute("statehidden", true)
  end
end

local function snapshotDrivers(state)
  local list = {}
  for frame, drivers in pairs(state.attrs) do
    for attribute, values in pairs(drivers) do
      list[#list + 1] = { frame = frame, attribute = attribute, values = values }
    end
  end

  return list
end

local function stillRegistered(state, driver)
  local drivers = state.attrs[driver.frame]

  return drivers ~= nil and drivers[driver.attribute] == driver.values
end

local function update(w, state)
  for _, driver in ipairs(snapshotDrivers(state)) do
    if stillRegistered(state, driver) then
      resolveDriver(w, driver.frame, driver.attribute, driver.values)
    end
  end
  local cache = {}
  local watchers = {}
  for frame, asState in pairs(state.watchers) do
    watchers[#watchers + 1] = { frame = frame, asState = asState }
  end
  for _, watch in ipairs(watchers) do
    if state.watchers[watch.frame] == watch.asState then
      updateWatch(w, watch.frame, watch.asState, cache)
    end
  end
end

local arm

local function tick(w, state)
  state.ticker = nil
  secure(w, update, w, state)
  if wanted(state) and not state.ticker then
    arm(w, state, UPDATE_THROTTLE)
  end
end

-- Replaces the pending update with one due after delay seconds of world time.
function arm(w, state, delay)
  if state.ticker then
    state.ticker:Cancel()
  end
  state.ticker = w:schedule(delay, function()
    tick(w, state)
  end, 1)
end

-- The first driver or watch starts the timer, due on the next advance (the manager's first OnUpdate).
local function ensureTicker(w, state)
  if not (state.ticker and timerPending(w, state.ticker)) then
    arm(w, state, 0)
  end
end

local function releaseTicker(state)
  if state.ticker and not wanted(state) then
    state.ticker:Cancel()
    state.ticker = nil
  end
end

local function setDriver(w, state, frame, attribute, values)
  local drivers = state.attrs[frame] or {}
  state.attrs[frame] = drivers
  if values:match("^%s*$") then
    drivers[attribute] = nil
    state.attrs[frame] = next(drivers) ~= nil and drivers or nil
    releaseTicker(state)

    return
  end
  drivers[attribute] = values
  ensureTicker(w, state)
  resolveDriver(w, frame, attribute, values)
end

local function registerAttributeDriver(w, frame, attribute, values)
  local state = w.taint.driver
  local valid = type(attribute) == "string" and type(values) == "string" and attribute:sub(1, 1) ~= "_"
  if valid then
    secure(w, setDriver, w, state, frame, attribute, values)
  end
end

local function unregisterAttributeDriver(w, frame, attribute)
  local state = w.taint.driver
  if attribute then
    secure(w, setDriver, w, state, frame, attribute, "")

    return
  end
  state.attrs[frame] = nil
  releaseTicker(state)
end

local function registerUnitWatch(w, frame, asState)
  local state = w.taint.driver
  state.watchers[frame] = asState and true or false
  ensureTicker(w, state)
  secure(w, updateWatch, w, frame, state.watchers[frame], {})
end

local function unregisterUnitWatch(w, frame)
  local state = w.taint.driver
  state.watchers[frame] = nil
  releaseTicker(state)
end

-- Brings the next update forward when one of the manager's events fires.
local function resetOnEvents(w, state)
  local fire = w.fire
  w.fire = function(self, event, ...)
    if RESET_EVENTS[event] and wanted(state) then
      arm(w, state, 0)
    end

    return fire(self, event, ...)
  end
end

function M.install(w)
  local state = { attrs = {}, watchers = {} }
  w.taint.driver = state
  resetOnEvents(w, state)
  local function define(name, fn)
    w:install(name, function(...)
      return fn(w, ...)
    end, FRAMEXML)
  end
  define("RegisterAttributeDriver", registerAttributeDriver)
  define("UnregisterAttributeDriver", unregisterAttributeDriver)
  define("RegisterStateDriver", function(world, frame, name, values)
    return registerAttributeDriver(world, frame, "state-" .. name, values)
  end)
  define("UnregisterStateDriver", function(world, frame, name)
    return unregisterAttributeDriver(world, frame, "state-" .. name)
  end)
  define("RegisterUnitWatch", registerUnitWatch)
  define("UnregisterUnitWatch", unregisterUnitWatch)
  define("UnitWatchRegistered", function(world, frame)
    return world.taint.driver.watchers[frame] ~= nil
  end)
end

return M
