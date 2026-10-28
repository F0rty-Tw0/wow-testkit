-- The modified-attribute lookup of secure buttons: modifier prefix, button suffix, wildcards and useparent, the unit a click
-- acts on, and the SecureButton_* globals that expose them.
-- source: extract retail 70575 blizzard_framexml/securetemplates.lua (lines cited per function); the code is the kit's.
local Attributes = require("ui.behaviour_attributes")
local SecureEnv = require("secure_env")

local M = {}

-- Localized: addon code may assign globals of the same names.
local tostring, tonumber = tostring, tonumber
local gsub = string.gsub

local FRAMEXML = { gate = "framexml", flavors = {} }

local function attributes(w, frame)
  return w.ui.state[frame].attributes
end

-- The result of the global at path called with args, or nil when the flavour lacks it.
function M.query(path, ...)
  local fn = SecureEnv.resolve(path)
  return fn and fn(...)
end
local query = M.query

-- source: `:33-68` (ParseSplitModifierString, SecureButton_ParseModifierString): the first "MODIFIER" or "MODIFIER:prefix" clause whose modified click is
-- held gives its prefix (or the lowercased modifier).
function M.parseModifierString(msg)
  for clause in tostring(msg):gmatch("[^,]+") do
    local mod, rep = clause:match("^([^:]*):?(.*)$")
    if query("IsModifiedClick", mod) then
      return rep ~= "" and rep or mod:lower()
    end
  end
  return nil
end

-- source: `:70-99` (the frame's `modifiers` attribute, else alt-ctrl-shift- for the keys held).
function M.modifierPrefix(w, frame)
  local list = attributes(w, frame) and attributes(w, frame).modifiers
  if list then
    local prefix = M.parseModifierString(list)
    if prefix then
      return prefix .. "-"
    end
  end
  local prefix = ""
  if query("IsShiftKeyDown") then
    prefix = "shift-" .. prefix
  end
  if query("IsControlKeyDown") then
    prefix = "ctrl-" .. prefix
  end
  if query("IsAltKeyDown") then
    prefix = "alt-" .. prefix
  end
  return prefix
end

-- source: `:101-117` (SecureButton_GetButtonSuffix)
function M.buttonSuffix(button)
  if button == "LeftButton" then
    return "1"
  elseif button == "RightButton" then
    return "2"
  elseif button == "MiddleButton" then
    return "3"
  elseif button and button ~= "" then
    local n = tostring(button):match("^Button(%d+)$")
    n = n and tonumber(n)
    return n and n >= 4 and n <= 31 and tostring(n) or "-" .. tostring(button)
  end
  return ""
end

-- source: `:119-137`: the engine lookup (ui/behaviour_attributes.lua), then the parent when the frame has
-- `useparent-<name>` or `useparent*`; an empty string is ATTRIBUTE_NOOP, which counts as unset.
function M.modifiedAttribute(w, frame, name, button, prefix, suffix)
  prefix = prefix or M.modifierPrefix(w, frame)
  suffix = suffix or M.buttonSuffix(button)
  local st = w.ui.state[frame]
  local value = Attributes.modified(st.attributes, prefix, name, suffix)
  if value == nil and st.attributes and (st.attributes["useparent-" .. name:lower()] or st.attributes["useparent*"]) then
    local parent = st.parent
    if parent and w.ui.state[parent] then
      value = M.modifiedAttribute(w, parent, name, button, prefix, suffix)
    end
  end
  if value == "" then
    return nil
  end
  return value
end

function M.attribute(w, frame, name)
  return M.modifiedAttribute(w, frame, name, nil, "", "")
end

-- source: `:143-199` (SecureButton_GetModifiedUnit) unit, unitsuffix (raid1pet is raidpet1, playerpet is pet), then the self-cast and focus-cast modifiers.
-- Assumed (the vehicle and mouseover-cast branches are not modelled).
function M.modifiedUnit(w, frame, button)
  local unit = M.modifiedAttribute(w, frame, "unit", button)
  if unit then
    local unitsuffix = M.modifiedAttribute(w, frame, "unitsuffix", button)
    if unitsuffix then
      unit = gsub(unit .. unitsuffix, "^([^%d]+)([%d]+)[pP][eE][tT]", "%1pet%2")
      unit = gsub(unit, "^[pP][lL][aA][yY][eE][rR][pP][eE][tT]", "pet")
    end
    return unit
  elseif M.modifiedAttribute(w, frame, "checkselfcast", button) and query("IsModifiedClick", "SELFCAST") then
    return "player"
  elseif M.modifiedAttribute(w, frame, "checkfocuscast", button) and query("IsModifiedClick", "FOCUSCAST") then
    return "focus"
  end
  return nil
end

-- source: `:201-212` (SecureButton_GetUnit)
function M.unitOf(w, frame)
  local unit = M.attribute(w, frame, "unit")
  if unit then
    local unitsuffix = M.attribute(w, frame, "unitsuffix")
    return unitsuffix and gsub(unit .. unitsuffix, "^([^%d]+)([%d]+)[pP][eE][tT]", "%1pet%2") or unit
  end
  return nil
end

function M.install(w)
  local function define(name, fn)
    w:install(name, function(...)
      return fn(w, ...)
    end, FRAMEXML)
  end
  define("SecureButton_GetModifiedAttribute", M.modifiedAttribute)
  define("SecureButton_GetAttribute", M.attribute)
  define("SecureButton_GetModifierPrefix", M.modifierPrefix)
  define("SecureButton_GetModifiedUnit", M.modifiedUnit)
  define("SecureButton_GetUnit", M.unitOf)
  w:install("SecureButton_GetButtonSuffix", M.buttonSuffix, FRAMEXML)
  w:install("SecureButton_ParseModifierString", M.parseModifierString, FRAMEXML)
end

return M
