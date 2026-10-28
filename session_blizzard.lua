-- The session side of the viewer's Blizzard panel: the snapshot's session.blizzard block (the layer's summary, whether an
-- extract is there, the Edit Mode layouts and the WTF import counts) and the state patches that set action slots and the
-- active layout through Scenario:actions and Scenario:editMode (engine context).
local M = {}

local BlizzardUi = require("blizzard_ui")
local EditMode = require("game.editmode")
local Json = require("json")
local State = require("game.state")

local MAX_SLOT = 180
local BIND_LINE = "^%s*bind%s+%S+%s+%S"

local function fail(message)
  error("state: " .. message, 0)
end

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
-- active (the client's activeLayout: 1 and 2 are the presets) and wtf (wtfCounts).
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
  return info
end

local function isWhole(value, low, high)
  return type(value) == "number" and value % 1 == 0 and value >= low and value <= high
end

-- actions with each slot key (a number, or the decimal string a JSON object key is) as a number. Raises on a slot
-- outside 1..180 or a value that is neither a fields table nor false.
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

-- Raises on the first malformed actions or editMode field of patch, before anything is applied.
function M.check(sess, patch)
  if patch.actions ~= nil then
    M.slots(patch.actions)
  end
  if patch.editMode ~= nil then
    checkEditMode(sess, patch.editMode)
  end
end

-- Applies a checked patch: the slots go to Scenario:actions and merge into sess.state.actions (keyed by the slot as a
-- string, so the state encodes as a JSON object; a reload applies it again); the active layout goes to Scenario:editMode
-- and is not kept, since a reload imports the layouts again.
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
end

return M
