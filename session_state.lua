-- Session mock state, set from the viewer's state panel: unit fixtures, the mouseover unit, modifier keys, the combat
-- flag and the group kind. The world reads modifiers, combat and group from w.mock through game/keys.lua (IsShiftKeyDown
-- and its siblings) and game/group.lua (InCombatLockdown, IsInGroup and theirs); a changed flag fires the event the client
-- fires for it. The Blizzard panel's action slots, active Edit Mode layout and open window go through session_blizzard.lua.
local M = {}

local Json = require("json")
local SessionBlizzard = require("session_blizzard")

local GROUPS = { none = true, party = true, raid = true }
local MODIFIERS = { shift = true, ctrl = true, alt = true }
local DEFAULT_MODIFIERS = { shift = false, ctrl = false, alt = false }
local FIELDS = { units = true, mouseover = true, modifiers = true, combat = true, group = true, actions = true, editMode = true, window = true }

local function sortedKeys(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function fail(message)
  error("state: " .. message, 0)
end

local function checkModifiers(modifiers)
  if type(modifiers) ~= "table" then
    fail("modifiers must be an object of shift, ctrl, alt")
  end
  for key, down in pairs(modifiers) do
    if not MODIFIERS[key] then
      fail("unknown modifier '" .. tostring(key) .. "'; valid: shift, ctrl, alt")
    elseif type(down) ~= "boolean" then
      fail("modifiers." .. key .. " must be true or false")
    end
  end
end

-- Raises on the first malformed field, before anything is applied.
local function check(sess, patch)
  for key in pairs(patch) do
    if not FIELDS[key] then
      fail("unknown field '" .. tostring(key) .. "'; valid: units, mouseover, modifiers, combat, group, actions, editMode, window")
    end
  end
  if patch.units ~= nil and type(patch.units) ~= "table" then
    fail("units must be an object of unit fixtures")
  elseif patch.mouseover ~= nil and type(patch.mouseover) ~= "string" then
    fail("mouseover must be a unit token")
  elseif patch.combat ~= nil and type(patch.combat) ~= "boolean" then
    fail("combat must be true or false")
  elseif patch.group ~= nil and not GROUPS[patch.group] then
    fail("group must be none, party or raid")
  end
  if patch.modifiers ~= nil then
    checkModifiers(patch.modifiers)
  end
  SessionBlizzard.check(sess, patch)
end

local function copy(t)
  local out = {}
  for key, value in pairs(t) do
    out[key] = value
  end
  return out
end

-- Merges { modifiers, combat, group } into w.mock (Game.install created it; later phases add their own fields beside
-- these) and creates sess.state. The APIs that read them are game/keys.lua and game/group.lua.
function M.install(w, sess)
  w:setMock({ modifiers = DEFAULT_MODIFIERS, combat = false, group = "none" })
  sess.state = { units = Json.object({}), modifiers = copy(DEFAULT_MODIFIERS), combat = false, group = "none" }
end

local function applyUnits(sess, units)
  for _, token in ipairs(sortedKeys(units)) do
    sess.w:unit(token, units[token])
    sess.state.units[token] = units[token]
  end
end

-- Sets the flag and fires event when value differs from the current one.
local function toggle(sess, key, value, event)
  if value == nil or value == sess.w.mock[key] then
    return
  end
  -- source: confirmed (row G8) combat lockdown begins after PLAYER_REGEN_DISABLED fires and ends before
  -- PLAYER_REGEN_ENABLED fires, so entering combat fires first and sets after.
  if key == "combat" and value then
    sess.s:fireIfKnown(event)
    sess.w.mock[key] = value
    return
  end
  sess.w.mock[key] = value
  sess.s:fireIfKnown(event)
end

-- Checks patch, merges it into sess.state and applies it to the world. Returns sess.state, its combat and group read from
-- w.mock, which the combat world also sets.
function M.apply(sess, patch)
  check(sess, patch)
  if patch.units then
    applyUnits(sess, patch.units)
  end
  if patch.mouseover then
    sess.w:mouseover(patch.mouseover)
    sess.state.mouseover = patch.mouseover
  end
  for key, down in pairs(patch.modifiers or {}) do
    sess.w.mock.modifiers[key], sess.state.modifiers[key] = down, down
  end
  toggle(sess, "combat", patch.combat, patch.combat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
  toggle(sess, "group", patch.group, "GROUP_ROSTER_UPDATE")
  sess.state.combat, sess.state.group = sess.w.mock.combat, sess.w.mock.group
  SessionBlizzard.apply(sess, patch)
  return sess.state
end

return M
