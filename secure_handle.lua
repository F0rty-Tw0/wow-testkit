-- The methods of a frame handle (`self` and `control` in a snippet): getters and setters that forward to the frame, the
-- ones that take or return handles, Show and Hide (which keep the `statehidden` attribute), SetAttribute's checks, frame
-- references, and Run, RunFor, RunAttribute, ChildUpdate and CallMethod. A handle works on a frame out of combat, and in
-- combat on a protected one only (frameOf). Not modelled: the SetBinding family and the auto-hide calls.
-- source: extract retail 70575 blizzard_restrictedaddonenvironment/restrictedframes.lua:58-830 (HANDLE:*); the code is the
-- kit's.
local SecureAttributes = require("secure_attributes")
local SecureEnv = require("secure_env")
local Taint = require("taint")

local M = {}

-- Localized: addon code may assign globals of the same names.
local type, tostring, error, ipairs, select, unpack, getmetatable = type, tostring, error, ipairs, select, unpack, getmetatable

local methods = SecureEnv.handleMethods

-- The names that forward to the frame method of the same name, arguments turned from handles into frames.
local FORWARDED = [[
  GetName GetID IsShown IsVisible GetWidth GetHeight GetScale GetEffectiveScale GetRect GetFrameLevel GetFrameStrata
  IsMouseEnabled IsMouseClickEnabled IsMouseMotionEnabled IsKeyboardEnabled IsGamePadButtonEnabled IsGamePadStickEnabled
  GetObjectType IsObjectType GetMousePosition IsUnderMouse GetNumPoints SetID SetWidth SetHeight SetScale SetAlpha
  ClearAllPoints Raise Lower SetFrameLevel SetFrameStrata EnableMouse EnableKeyboard EnableGamePadButton EnableGamePadStick
  Enable Disable SetPoint SetAllPoints SetParent
]]

local function inCombat(w)
  return w.mock ~= nil and w.mock.combat == true
end

-- source: `:56` (LOCAL_CHECK_Frame, a copy of the frame metatable's __index) the widget class's own method, so a field an
-- addon set on the frame is never called by secure code.
local function method(frame, name)
  return getmetatable(frame).__index[name]
end

-- source: `:58-102` the frame a handle stands for when a snippet may act on it: any frame out of combat, a protected one in
-- combat, never a forbidden one.
local function frameOf(w, handle)
  local frame = SecureEnv.frameOf(w, handle)
  if frame and not w.ui.state[frame].forbidden and (not inCombat(w) or w.taint.isProtected(w, frame)) then
    return frame
  end
  error("Invalid frame handle", 0)
end

-- The handle for frame when a snippet may reach it, else nil (the FrameHandleMapper rule).
local function handleFor(w, frame)
  local st = frame and w.ui.state[frame]
  if st and not st.forbidden and (not inCombat(w) or w.taint.isProtected(w, frame)) then
    return SecureEnv.handle(w, frame)
  end
  return nil
end

-- A value a snippet may hold: a scalar or a handle; tables, functions and the like become nil.
local function scrub(w, value)
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" or SecureEnv.frameOf(w, value) then
    return value
  end
  return nil
end

for name in FORWARDED:gmatch("%S+") do
  methods[name] = function(w, handle, ...)
    local frame = frameOf(w, handle)
    local fn = method(frame, name)
    if fn then
      return fn(frame, SecureEnv.toFrames(w, ...))
    end
  end
end

function methods.IsProtected(w, handle)
  local frame = SecureEnv.frameOf(w, handle)
  if not frame then
    error("Invalid frame handle", 0)
  end
  return w.taint.isProtected(w, frame)
end

function methods.GetAttribute(w, handle, name)
  if type(name) ~= "string" or name:match("^_") then
    return nil
  end
  local frame = frameOf(w, handle)
  return scrub(w, method(frame, "GetAttribute")(frame, name))
end

function methods.GetFrameRef(w, handle, label)
  if type(label) ~= "string" then
    return nil
  end
  local frame = frameOf(w, handle)
  local value = method(frame, "GetAttribute")(frame, "frameref-" .. label)
  return SecureEnv.frameOf(w, value) and value or nil
end

function methods.GetEffectiveAttribute(w, handle, name, button, prefix, suffix)
  if type(name) ~= "string" or name:match("^_") then
    return nil
  end
  prefix = prefix ~= nil and tostring(prefix) or nil
  if prefix and prefix:match("^_") then
    prefix = nil
  end
  suffix = suffix ~= nil and tostring(suffix) or nil
  return scrub(w, SecureAttributes.modifiedAttribute(w, frameOf(w, handle), name, button ~= nil and tostring(button) or nil, prefix, suffix))
end

function methods.SetAttribute(w, handle, name, value)
  if type(name) ~= "string" or name:match("^_") then
    error("Invalid attribute name", 0)
  end
  local kind = type(value)
  if kind ~= "string" and kind ~= "nil" and kind ~= "number" and kind ~= "boolean" and not SecureEnv.frameOf(w, value) then
    error("Invalid attribute value", 0)
  end
  local frame = frameOf(w, handle)
  method(frame, "SetAttribute")(frame, name, value)
end

local function handlesOf(w, ...)
  local out, n = {}, 0
  for i = 1, select("#", ...) do
    local handle = handleFor(w, (select(i, ...)))
    if handle then
      n = n + 1
      out[n] = handle
    end
  end
  return out, n
end

local function children(w, handle)
  local frame = frameOf(w, handle)
  return method(frame, "GetChildren")(frame)
end

function methods.GetChildren(w, handle)
  local out, n = handlesOf(w, children(w, handle))
  return unpack(out, 1, n)
end

function methods.GetChildList(w, handle, tbl)
  local out, n = handlesOf(w, children(w, handle))
  for i = 1, n do
    tbl[#tbl + 1] = out[i]
  end
  return tbl
end

function methods.GetParent(w, handle)
  local frame = frameOf(w, handle)
  return handleFor(w, method(frame, "GetParent")(frame))
end

function methods.GetPoint(w, handle, i)
  local frame = frameOf(w, handle)
  local point, relative, relativePoint, x, y = method(frame, "GetPoint")(frame, i)
  local relativeHandle = relative and handleFor(w, relative)
  if relativeHandle or not relative then
    return point, relativeHandle, relativePoint, x, y
  end
  return nil
end

-- source: `:394-408` Show and Hide record the intent in `statehidden` unless skipAttr is given.
function methods.Show(w, handle, skipAttr)
  local frame = frameOf(w, handle)
  method(frame, "Show")(frame)
  if not skipAttr then
    method(frame, "SetAttribute")(frame, "statehidden", nil)
  end
end

function methods.Hide(w, handle, skipAttr)
  local frame = frameOf(w, handle)
  method(frame, "Hide")(frame)
  if not skipAttr then
    method(frame, "SetAttribute")(frame, "statehidden", true)
  end
end

function methods.Run(w, handle, body, ...)
  local frame = frameOf(w, handle)
  if type(body) ~= "string" then
    error("Invalid function body", 0)
  end
  return SecureEnv.call(w, frame, frame, "self,...", body, ...)
end

function methods.RunFor(w, handle, other, body, ...)
  local frame = frameOf(w, handle)
  if other ~= nil and not SecureEnv.frameOf(w, other) then
    error("Invalid handle for other frame", 0)
  elseif type(body) ~= "string" then
    error("Invalid function body", 0)
  end
  return SecureEnv.call(w, SecureEnv.frameOf(w, other) or frame, frame, "self,...", body, ...)
end

function methods.RunAttribute(w, handle, attribute, ...)
  local frame = frameOf(w, handle)
  if type(attribute) ~= "string" then
    error("Invalid snippet attribute", 0)
  end
  local body = method(frame, "GetAttribute")(frame, attribute)
  if type(body) ~= "string" then
    error("Invalid snippet body", 0)
  end
  return SecureEnv.call(w, frame, frame, "self,...", body, ...)
end

-- source: `:768-802` each protected child runs `_childupdate-<id>`, else `_childupdate`, with (self, scriptid, message).
function methods.ChildUpdate(w, handle, scriptid, message)
  local frame = frameOf(w, handle)
  local attribute = scriptid ~= nil and "_childupdate-" .. tostring(scriptid)
  for _, child in ipairs({ method(frame, "GetChildren")(frame) }) do
    if w.taint.isProtected(w, child) then
      local get = method(child, "GetAttribute")
      local body = attribute and get(child, attribute) or get(child, "_childupdate")
      if type(body) == "string" then
        SecureEnv.call(w, child, frame, "self,scriptid,message", body, scriptid, message)
      end
    end
  end
end

-- source: `:805-841` the method runs after forceinsecure, its taint dropped on return, and an error goes to the error
-- handler without stopping the snippet.
function methods.CallMethod(w, handle, name, ...)
  local frame = frameOf(w, handle)
  if type(name) ~= "string" then
    error("Method name must be a string", 0)
  end
  Taint.secure(w, function(...)
    w:try(function(...)
      Taint.force(w)
      local fn = frame[name]
      if type(fn) ~= "function" then
        error("Invalid method '" .. name .. "'", 0)
      end
      fn(frame, ...)
    end, ...)
  end, ...)
end

return M
