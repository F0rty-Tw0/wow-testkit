-- The scripts the SecureHandler templates register: each runs the attribute named for its event as a snippet on the frame
-- (secure_env.lua), and a drag script picks up what the snippet returns.
-- source: extract retail 70575 blizzard_restrictedaddonenvironment/securehandlers.lua and securehandlertemplates.xml:6-105
-- (the script bodies); the code is the kit's.
local SecureEnv = require("secure_env")
local Taint = require("taint")

local M = {}

-- Localized: addon code may assign globals of the same names.
local type, tostring = type, tostring

local function selfExecute(w, frame, signature, body, ...)
  if type(body) == "string" then
    return SecureEnv.call(w, frame, frame, signature, body, ...)
  end
end

local function otherExecute(w, header, frame, signature, body, ...)
  if type(body) == "string" then
    return SecureEnv.call(w, frame, header, signature, body, ...)
  end
end

-- Runs the snippet in attribute `attribute` of frame, if it has one.
local function onSimpleEvent(w, frame, attribute)
  selfExecute(w, frame, "self", frame:GetAttribute(attribute))
end

local function onClick(w, frame, attribute, button, down)
  selfExecute(w, frame, "self,button,down", frame:GetAttribute(attribute), button, down)
end

local function onMouseUpDown(w, frame, attribute, button)
  selfExecute(w, frame, "self,button", frame:GetAttribute(attribute), button)
end

local function onMouseWheel(w, frame, attribute, delta)
  selfExecute(w, frame, "self,delta", frame:GetAttribute(attribute), delta)
end

local function onStateChanged(w, frame, name, value)
  local stateid = tostring(name):match("^state%-(.+)")
  if stateid then
    selfExecute(w, frame, "self,stateid,newstate", frame:GetAttribute("_onstate-" .. stateid), stateid, value)
  end
end

local function onAttributeChanged(w, frame, name, value)
  if not tostring(name):match("^_") then
    selfExecute(w, frame, "self,name,value", frame:GetAttribute("_onattributechanged"), name, value)
  end
end

local PICKUP = {
  action = "PickupAction",
  bag = "PickupBagFromSlot",
  bagslot = "C_Container.PickupContainerItem",
  inventory = "PickupInventoryItem",
  item = "C_Item.PickupItem",
  macro = "PickupMacro",
  merchant = "PickupMerchantItem",
  petaction = "PickupPetAction",
  money = "PickupPlayerMoney",
  spell = "C_Spell.PickupSpell",
  companion = "PickupCompanion",
  equipmentset = "C_EquipmentSet.PickupEquipmentSet",
}

-- source: `:128-166` (PickupAny, SecureHandler_OnDragEvent) what a drag snippet returns is what the cursor picks up: a kind and its arguments, "clear" first
-- to empty the cursor.
local function pickupAny(w, kind, target, detail, ...)
  if kind == "clear" then
    local clear = SecureEnv.resolve(w, "ClearCursor")
    if clear then
      clear()
    end
    kind, target, detail = target, detail, ...
  end
  local pickup = PICKUP[kind] and SecureEnv.resolve(w, PICKUP[kind])
  if pickup then
    pickup(target, detail)
  end
end

local function cursorInfo(w)
  local fn = SecureEnv.resolve(w, "GetCursorInfo")
  if fn then
    return fn()
  end
end

local function onDragEvent(w, frame, attribute, button)
  local body = frame:GetAttribute(attribute)
  if body then
    pickupAny(w, selfExecute(w, frame, "self,button,kind,value,...", body, button, cursorInfo(w)))
  end
end

-- source: extract retail 70575 blizzard_restrictedaddonenvironment/securehandlers.lua:427-429 (the API runs "via attribute
-- sets so as to allow secure execution") and :697-698 (SecureHandlerExecute is two SetAttribute calls): a template's
-- snippet handler runs as secure execution, whoever fired its script. Assumed (ruling B1) for every script below.
local function secure(fn)
  return function(w, self, ...)
    return Taint.secure(w, fn, w, self, ...)
  end
end

-- The scripts each template registers, as fn(w, self, ...) (ui/template_apply.lua passes the world).
M.scripts = {
  state = {
    OnAttributeChanged = secure(onStateChanged),
  },
  attribute = {
    OnAttributeChanged = secure(onAttributeChanged),
  },
  click = {
    OnClick = secure(function(w, self, button, down)
      onClick(w, self, "_onclick", button, down)
    end),
  },
  doubleClick = {
    OnDoubleClick = secure(function(w, self, button)
      onClick(w, self, "_ondoubleclick", button)
    end),
  },
  drag = {
    OnDragStart = secure(function(w, self, button)
      onDragEvent(w, self, "_ondragstart", button)
    end),
    OnReceiveDrag = secure(function(w, self)
      onDragEvent(w, self, "_onreceivedrag")
    end),
  },
  showHide = {
    OnShow = secure(function(w, self)
      onSimpleEvent(w, self, "_onshow")
    end),
    OnHide = secure(function(w, self)
      onSimpleEvent(w, self, "_onhide")
    end),
  },
  mouseUpDown = {
    OnMouseUp = secure(function(w, self, button)
      onMouseUpDown(w, self, "_onmouseup", button)
    end),
    OnMouseDown = secure(function(w, self, button)
      onMouseUpDown(w, self, "_onmousedown", button)
    end),
  },
  mouseWheel = {
    OnLoad = function(_, self)
      self:EnableMouseWheel(true)
    end,
    OnMouseWheel = secure(function(w, self, delta)
      onMouseWheel(w, self, "_onmousewheel", delta)
    end),
  },
  enterLeave = {
    OnEnter = secure(function(w, self, motion)
      if motion then
        self:SetAttribute("_entered", true)
        onSimpleEvent(w, self, "_onenter")
      end
    end),
    OnLeave = secure(function(w, self, motion)
      if motion and self:GetAttribute("_entered") then
        self:SetAttribute("_entered", nil)
        onSimpleEvent(w, self, "_onleave")
      end
    end),
  },
}

M.selfExecute, M.otherExecute, M.pickupAny, M.cursorInfo = selfExecute, otherExecute, pickupAny, cursorInfo
M.onSimpleEvent, M.onClick, M.onMouseUpDown, M.onMouseWheel = onSimpleEvent, onClick, onMouseUpDown, onMouseWheel
M.onStateChanged, M.onAttributeChanged, M.onDragEvent = onStateChanged, onAttributeChanged, onDragEvent

return M
