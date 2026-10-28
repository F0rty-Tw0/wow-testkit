-- The wrappers WrapScript puts on a frame's script: a pre body that can change or skip the original handler, and a post
-- body that runs after it. Each wrapper is the frame's own script (a later SetScript replaces it), keeping the handler it
-- replaced in `info.original`.
-- source: extract retail 70575 blizzard_restrictedaddonenvironment/securehandlers.lua (Wrapped_* functions); the code is the
-- kit's.
local Scripts = require("secure_scripts")
local SecureEnv = require("secure_env")

local M = {}

-- Localized: addon code may assign globals of the same names.
local type, tostring = type, tostring

local otherExecute, pickupAny, cursorInfo = Scripts.otherExecute, Scripts.pickupAny, Scripts.cursorInfo

local function inCombat(w)
  return w.mock ~= nil and w.mock.combat == true
end

-- source: `:267-269` (IsWrapEligible) the pre body runs outside combat, and in combat only on a protected frame.
local function eligible(w, frame)
  return not inCombat(w) or (w.taint.isProtected(w, frame))
end

-- source: `:256-264` (SafeCallWrappedHandler) the original handler runs with its own taint, an error goes to the error
-- handler.
local function callOriginal(w, info, frame, ...)
  if type(info.original) == "function" then
    w:callAsAddon(info.original, frame, ...)
  end
end

local function post(w, info, frame, signature, ...)
  if info.postBody then
    otherExecute(w, info.header, frame, signature, info.postBody, ...)
  end
end

-- source: `:272-290` (Wrapped_Click): pre gets (self, button, down) and returns newbutton, message; false skips the original
-- and the post body, a string replaces the button; the post body runs only for a non-nil message.
local function wrappedClick(w, frame, info, button, down, ...)
  local message
  if eligible(w, frame) then
    local newbutton
    newbutton, message = otherExecute(w, info.header, frame, "self,button,down", info.preBody, button, down)
    if newbutton == false then
      return
    elseif newbutton then
      button = tostring(newbutton)
    end
  end
  callOriginal(w, info, frame, button, down, ...)
  if message ~= nil then
    post(w, info, frame, "self,message,button,down", message, button, down)
  end
end

-- source: `:292-329` (Wrapped_OnEnter, Wrapped_OnLeave): only on motion; the pre body of OnLeave only after an OnEnter that
-- set `_wrapentered`.
local function wrappedEnter(w, frame, info, motion, ...)
  local allow, message
  if motion then
    frame:SetAttribute("_wrapentered", true)
    if eligible(w, frame) then
      allow, message = otherExecute(w, info.header, frame, "self", info.preBody)
    end
    if allow == false then
      return
    end
  end
  callOriginal(w, info, frame, motion, ...)
  if message ~= nil then
    post(w, info, frame, "self,message", message)
  end
end

local function wrappedLeave(w, frame, info, motion, ...)
  local allow, message
  if motion and frame:GetAttribute("_wrapentered") then
    frame:SetAttribute("_wrapentered", nil)
    if eligible(w, frame) then
      allow, message = otherExecute(w, info.header, frame, "self", info.preBody)
      if allow == false then
        return
      end
    end
  end
  callOriginal(w, info, frame, motion, ...)
  if message ~= nil then
    post(w, info, frame, "self,message")
  end
end

-- source: `:331-348` (CreateSimpleWrapper): pre gets the arguments, post gets the message first.
local function simpleWrap(beforeSignature, afterSignature)
  return function(w, frame, info, ...)
    local allow, message
    if eligible(w, frame) then
      allow, message = otherExecute(w, info.header, frame, beforeSignature, info.preBody, ...)
      if allow == false then
        return
      end
    end
    callOriginal(w, info, frame, ...)
    if message ~= nil then
      post(w, info, frame, afterSignature, message, ...)
    end
  end
end

-- source: `:353-378` (Wrapped_Drag): the pre body gets (self, button, kind, value, ...) and returns false (skip), "message"
-- and the message, or a cursor kind that is picked up instead.
local function wrappedDrag(w, frame, info, button, ...)
  local message
  if eligible(w, frame) then
    local kind, target, x1, x2, x3 = SecureEnv.call(w, frame, info.header, "self,button,kind,value,...", info.preBody, button, cursorInfo())
    if kind == false then
      return
    elseif kind == "message" then
      message = target
    elseif kind then
      return pickupAny(kind, target, x1, x2, x3)
    end
  end
  callOriginal(w, info, frame, button, ...)
  if message ~= nil then
    post(w, info, frame, "self,message,button", message, button, ...)
  end
end

-- source: `:380-392` (Wrapped_Attribute): names starting with _ are not wrapped.
local function wrappedAttribute(w, frame, info, name, value, ...)
  local allow, message
  if not tostring(name):match("^_") and eligible(w, frame) then
    allow, message = otherExecute(w, info.header, frame, "self,name,value", info.preBody, name, value)
    if allow == false then
      return
    end
  end
  callOriginal(w, info, frame, name, value, ...)
  if message ~= nil then
    post(w, info, frame, "self,message,name,value", message, name, value)
  end
end

-- source: `:394-413` (LOCAL_Wrap_Handlers) the scripts that can be wrapped.
M.wrappers = {
  OnClick = wrappedClick,
  OnDoubleClick = wrappedClick,
  PreClick = wrappedClick,
  PostClick = wrappedClick,
  OnEnter = wrappedEnter,
  OnLeave = wrappedLeave,
  OnShow = simpleWrap("self", "self,message"),
  OnHide = simpleWrap("self", "self,message"),
  OnDragStart = wrappedDrag,
  OnReceiveDrag = wrappedDrag,
  OnMouseWheel = simpleWrap("self,offset", "self,message,offset"),
  OnAttributeChanged = wrappedAttribute,
}

return M
