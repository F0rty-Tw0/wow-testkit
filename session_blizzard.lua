-- The session side of the viewer's Blizzard panel: the snapshot's session.blizzard block (the layer's summary, whether an
-- extract is there, the Edit Mode layouts, the WTF import counts and the window picker's windows) and the state patches that
-- set action slots, the active layout and the open Blizzard window through Scenario:actions, Scenario:editMode and
-- Scenario:openWindow (engine context).
local M = {}

local BlizzardUi = require("blizzard_ui")
local BlizzardWindows = require("blizzard_windows")
local EditMode = require("game.editmode")
local Json = require("json")
local State = require("game.state")
local WindowsDemo = require("windows_demo")

local MAX_SLOT = 180
local BIND_LINE = "^%s*bind%s+%S+%s+%S"

local function fail(message)
  error("state: " .. message, 0)
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

-- The windows a state patch may name, sorted: every window blizzard_window_specs.lua holds on some flavor. "close"
-- closes the open one.
local WINDOWS = {}
for _, windows in pairs(BlizzardWindows.WINDOWS) do
  for window in pairs(windows) do
    if not contains(WINDOWS, window) then
      WINDOWS[#WINDOWS + 1] = window
    end
  end
end
table.sort(WINDOWS)

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do
    n = n + 1
  end
  return n
end

-- { cvars, bindings, saved, layouts } of a WTF import (session_wtf.lua Wtf.open's table); saved counts the variables the
-- session started with, which the import seeds. nil without an import.
local function wtfCounts(sess)
  local wtf = sess.opts.wtfData
  if not wtf then
    return nil
  end
  local bindings = 0
  for line in (wtf.bindings or ""):gmatch("[^\r\n]+") do
    bindings = bindings + (line:match(BIND_LINE) and 1 or 0)
  end
  return { cvars = count(wtf.cvars), bindings = bindings, saved = count(sess.s.saved), layouts = #(wtf.editMode or {}) }
end

-- BlizzardUi.summary plus available (the world has a client extract), layouts = { layoutName... } (the saved layouts),
-- active (the client's activeLayout: 1 and 2 are the presets), wtf (wtfCounts), windows (BlizzardWindows.available: the
-- windows the picker offers) and open (the window a state patch opened, or nil).
function M.info(sess)
  local w = sess.w
  local info = BlizzardUi.summary(w)
  local mock = w.mock.editMode
  info.available = w.client ~= nil
  info.layouts = {}
  for i, layout in ipairs(mock.layouts) do
    info.layouts[i] = tostring(layout.layoutName)
  end
  info.active = mock.active
  info.wtf = wtfCounts(sess)
  info.windows = BlizzardWindows.available(w)
  info.open = sess.window
  return info
end

local function isWhole(value, low, high)
  return type(value) == "number" and value % 1 == 0 and value >= low and value <= high
end

-- Raises unless the slot's texture is a number or string and its count a whole number from 0, each when given: the
-- action bar fakes compare count and Blizzard's buttons set texture.
local function checkFields(slot, fields)
  local texture = fields.texture
  if texture ~= nil and type(texture) ~= "number" and type(texture) ~= "string" then
    fail("actions slot " .. slot .. " texture must be a number or a string")
  elseif fields.count ~= nil and not isWhole(fields.count, 0, math.huge) then
    fail("actions slot " .. slot .. " count must be a whole number from 0")
  end
end

-- actions with each slot key (a number, or the decimal string a JSON object key is) as a number. Raises on a slot
-- outside 1..180, a value that is neither a fields table nor false, or a malformed texture or count.
function M.slots(actions)
  if type(actions) ~= "table" then
    fail("actions must be an object of slot -> fields or false")
  end
  local out = {}
  for key, value in pairs(actions) do
    local slot = tonumber(key)
    if not isWhole(slot, 1, MAX_SLOT) then
      fail("actions slot '" .. tostring(key) .. "' must be a whole number from 1 to " .. MAX_SLOT)
    elseif value ~= false and type(value) ~= "table" then
      fail("actions slot " .. slot .. " must be fields or false")
    elseif value then
      checkFields(slot, value)
    end
    out[slot] = value
  end
  return out
end

-- Raises unless editMode is { active = n } with n a layout index the client accepts (1 .. saved layouts + presets).
local function checkEditMode(sess, editMode)
  if type(editMode) ~= "table" then
    fail("editMode must be { active = n }")
  end
  for key in pairs(editMode) do
    if key ~= "active" then
      fail("unknown editMode field '" .. tostring(key) .. "'; valid: active")
    end
  end
  local high = #sess.w.mock.editMode.layouts + EditMode.PRESET_COUNT
  if not isWhole(editMode.active, 1, high) then
    fail("editMode.active must be a whole number from 1 to " .. high)
  end
end

-- Raises unless window is "close" or a window of WINDOWS that the flavor has and the layer can show (BlizzardWindows.available,
-- so the picker and the endpoint accept the same names).
local function checkWindow(sess, window)
  local w = sess.w
  if window == "close" then
    return
  elseif not contains(WINDOWS, window) then
    fail("unknown window '" .. tostring(window) .. "'; valid: " .. table.concat(WINDOWS, ", ") .. ", close")
  elseif not BlizzardWindows.spec(w, window) then
    fail("no '" .. window .. "' window on " .. w.flavor)
  elseif not contains(BlizzardWindows.available(w), window) then
    local why = w.blizzard and "the extract has no " .. BlizzardWindows.spec(w, window).addon or "the Blizzard UI layer is off"
    fail("no '" .. window .. "' window available (" .. why .. ")")
  end
end

-- Raises on the first malformed actions, editMode or window field of patch, before anything is applied.
function M.check(sess, patch)
  if patch.actions ~= nil then
    M.slots(patch.actions)
  end
  if patch.editMode ~= nil then
    checkEditMode(sess, patch.editMode)
  end
  if patch.window ~= nil then
    checkWindow(sess, patch.window)
  end
end

-- Closes the open window, then opens window with a copy of its windows_demo.lua entry ("close" only closes). sess.window
-- names the open one; it is not kept in sess.state, so a reload logs in with no window open.
local function applyWindow(sess, window)
  local open = sess.window
  sess.window = nil
  if open then
    sess.s:closeWindow(open)
  end
  if window ~= "close" then
    sess.s:openWindow(window, State.merge({}, WindowsDemo[window]))
    sess.window = window
  end
end

-- Applies a checked patch: the slots go to Scenario:actions and merge into sess.state.actions (keyed by the slot as a
-- string, so the state encodes as a JSON object; a reload applies it again); the active layout goes to Scenario:editMode
-- and is not kept, since a reload imports the layouts again; the window goes to applyWindow.
function M.apply(sess, patch)
  if patch.actions then
    local slots = M.slots(patch.actions)
    sess.s:actions(slots)
    sess.state.actions = sess.state.actions or Json.object({})
    for slot, value in pairs(slots) do
      local key = tostring(slot)
      local kept = sess.state.actions[key]
      sess.state.actions[key] = value and State.merge(type(kept) == "table" and kept or {}, value)
    end
  end
  if patch.editMode then
    sess.s:editMode({ active = patch.editMode.active })
  end
  if patch.window then
    applyWindow(sess, patch.window)
  end
end

return M
