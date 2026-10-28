-- SecureActionButton and SecureUnitButton: the action each `type` attribute runs. A click acts with the taint it arrives with: a hardware
-- click (secure) casts, an addon's Click() stays tainted, so its protected call is refused by the gate in taint_protected.lua.
-- source: extract retail 70575 blizzard_framexml/securetemplates.lua (lines cited per function); the code is the kit's.
local SecureAttributes = require("secure_attributes")
local SecureEnv = require("secure_env")
local Taint = require("taint")
local WorldApi = require("world_api")

local M = {}

-- Localized: addon code may assign globals of the same names.
local rawget, type, tonumber, tostring, unpack = rawget, type, tonumber, tostring, unpack

local resolve = SecureEnv.resolve
local query = SecureAttributes.query
local modifiedAttribute = SecureAttributes.modifiedAttribute
local FRAMEXML = { gate = "framexml", flavors = {} }

-- source: `securetemplates.lua:262-584` the type names the kit models no action for: counted, nothing runs.
local UNMODELLED = {}
for name in
  ([[menu togglemenu actionbar actionrelease flyout multispell equipmentset leavevehicle destroytotem maintank mainassist
  raidtarget worldmarker teleporthome returnhome visithouse outfit]]):gmatch("%S+")
do
  UNMODELLED[name] = true
end

-- The values CancelUnitBuff-style paths read: CANCELABLE_ITEMS keys (main hand, off hand, ranged inventory slots).
local CANCELABLE_SLOTS = { [16] = true, [17] = true, [18] = true }

-- Calls the global at path with args; counts w.unscripted["secure:<kind>"] and returns nothing when the flavour lacks it.
local function call(w, kind, path, ...)
  local fn = resolve(w, path)
  if not fn then
    WorldApi.markUnscripted(w, "secure:" .. kind)
    return nil
  end
  return fn(...)
end

-- "13" is a slot, "1 3" a bag and slot, anything else an item name.
local function parseItem(item)
  local bag, slot = tostring(item):match("^(%d+)%s+(%d+)$")
  slot = slot or tostring(item):match("^(%d+)$")
  if bag or slot then
    return nil, tonumber(bag), tonumber(slot)
  end
  return item, nil, nil
end

-- source: `:262-584` (SECURE_ACTIONS.<type>); each calls the global the row names. fn(w, frame, unit, button, down, isKeyPress).
local ACTIONS = {}

function ACTIONS.spell(w, frame, unit, button)
  local spell = modifiedAttribute(w, frame, "spell", button)
  local id = tonumber(spell)
  if id then
    call(w, "spell", "CastSpellByID", id, unit)
  elseif spell then
    call(w, "spell", "CastSpellByName", spell, unit)
  end
end

function ACTIONS.toy(w, frame, _, button)
  local toy = modifiedAttribute(w, frame, "toy", button)
  if tonumber(toy) then
    call(w, "toy", "UseToy", tonumber(toy))
  elseif toy then
    call(w, "toy", "UseToyByName", toy)
  end
end

function ACTIONS.item(w, frame, unit, button)
  local item = modifiedAttribute(w, frame, "item", button)
  if not item then
    local bag, slot = modifiedAttribute(w, frame, "bag", button), modifiedAttribute(w, frame, "slot", button)
    item = bag and slot and (bag .. " " .. slot) or slot
  end
  if item then
    local name, bag, slot = parseItem(item)
    if name and query(w, "C_Item.IsEquippableItem", name) and not query(w, "C_Item.IsEquippedItem", name) then
      call(w, "item", "C_Item.EquipItemByName", name)
    else
      call(w, "item", "SecureCmdUseItem", name, bag, slot, unit)
    end
  end
end

function ACTIONS.macro(w, frame, _, button)
  local macro = modifiedAttribute(w, frame, "macro", button)
  if macro then
    call(w, "macro", "RunMacro", macro, button)
  else
    local text = modifiedAttribute(w, frame, "macrotext", button)
    if text then
      call(w, "macro", "C_Macro.RunMacroText", text, button)
    end
  end
end

function ACTIONS.target(w, _, unit)
  if not unit then
    return
  elseif unit == "none" then
    call(w, "target", "ClearTarget")
  elseif query(w, "SpellIsTargeting") then
    call(w, "target", "SpellTargetUnit", unit)
  elseif query(w, "CursorHasItem") then
    call(w, "target", "C_Item.DropItemOnUnit", unit)
  else
    call(w, "target", "TargetUnit", unit)
  end
end

function ACTIONS.focus(w, _, unit)
  return call(w, "focus", "FocusUnit", unit)
end

function ACTIONS.assist(w, _, unit)
  return call(w, "assist", "AssistUnit", unit)
end

function ACTIONS.stop(w)
  if query(w, "SpellIsTargeting") then
    call(w, "stop", "SpellStopTargeting")
  end
end

function ACTIONS.pet(w, frame, unit, button)
  local action = modifiedAttribute(w, frame, "action", button)
  if action then
    call(w, "pet", "CastPetAction", action, unit)
  end
end

function ACTIONS.action(w, frame, unit, button, _, isKeyPress)
  local action = frame.CalculateAction and frame:CalculateAction(button) or tonumber(modifiedAttribute(w, frame, "action", button))
  if action then
    call(w, "action", "UseAction", action, unit, button, isKeyPress)
  end
end

function ACTIONS.cancelaura(w, frame, _, button)
  local spell = modifiedAttribute(w, frame, "spell", button)
  local slot = tonumber(modifiedAttribute(w, frame, "target-slot", button))
  if spell then
    call(w, "cancelaura", "CancelSpellByName", spell)
  elseif slot and CANCELABLE_SLOTS[slot] then
    call(w, "cancelaura", "C_PaperDollInfo.CancelTemporaryEnchantment", slot)
  else
    local index = modifiedAttribute(w, frame, "index", button) or (frame.GetID and frame:GetID())
    if index then
      call(w, "cancelaura", "CancelUnitBuff", "player", index, modifiedAttribute(w, frame, "filter", button))
    end
  end
end

function ACTIONS.click(w, frame, _, button)
  local delegate = modifiedAttribute(w, frame, "clickbutton", button)
  local st = delegate and w.ui.state[delegate]
  if st and not st.forbidden then
    delegate:Click(button)
  end
end

function ACTIONS.attribute(w, frame, _, button)
  local target = modifiedAttribute(w, frame, "attribute-frame", button) or frame
  local name = modifiedAttribute(w, frame, "attribute-name", button)
  if name then
    target:SetAttribute(name, modifiedAttribute(w, frame, "attribute-value", button))
  end
end

local DOWN, UP, HOLD_RELEASE = 1, 2, 3

-- source: `:694-731` the button, unit and action type a press resolves to: the downbutton remap on a down press, the
-- harmbutton and helpbutton remaps by whether the unit can be attacked or assisted, no action when the unit does not exist
-- (unless it is "none").
local function convert(w, frame, button, pressType)
  if pressType == DOWN then
    button = modifiedAttribute(w, frame, "downbutton", button) or button
  end
  local unit = SecureAttributes.modifiedUnit(w, frame, button)
  if unit then
    local original = button
    if query(w, "UnitCanAttack", "player", unit) then
      button = modifiedAttribute(w, frame, "harmbutton", button) or button
    elseif query(w, "UnitCanAssist", "player", unit) then
      button = modifiedAttribute(w, frame, "helpbutton", button) or button
    end
    if button ~= original then
      unit = SecureAttributes.modifiedUnit(w, frame, button)
    end
  end
  if type(button) ~= "string" or (unit and unit ~= "none" and not query(w, "UnitExists", unit)) then
    return nil
  end
  return button, unit, modifiedAttribute(w, frame, pressType == HOLD_RELEASE and "typerelease" or "type", button)
end

-- source: `:733-760` (PerformAction): a type with no SECURE_ACTIONS entry runs the `_<type>` attribute or the frame's own
-- field of that name after forceinsecure (a function with (self, unit, button, isKeyPress, down), a string as a snippet).
local function perform(w, frame, button, unit, actionType, down, isKeyPress)
  if not (button and actionType) then
    return
  end
  local action = ACTIONS[actionType]
  if action then
    return action(w, frame, unit, button, down, isKeyPress)
  elseif UNMODELLED[actionType] then
    return WorldApi.markUnscripted(w, "secure:" .. actionType)
  end
  local handler = modifiedAttribute(w, frame, "_" .. actionType, button) or rawget(frame, actionType)
  if type(handler) == "function" then
    Taint.force(w)
    handler(frame, unit, button, isKeyPress, down)
  elseif type(handler) == "string" then
    require("secure_scripts").onClick(w, frame, "_" .. actionType, button, down)
  end
end

local function click(w, frame, inputButton, down, isKeyPress)
  local button, unit, actionType = convert(w, frame, inputButton, down and DOWN or UP)
  if button then
    perform(w, frame, button, unit, actionType, down, isKeyPress)
  end
end

function M.shouldUseOnKeyDown(w, frame)
  local use = SecureAttributes.attribute(w, frame, "useOnKeyDown")
  if use == nil then
    use = query(w, "GetCVarBool", "ActionButtonUseKeyDown")
  end
  return use
end

-- source: `:805-829` (SecureActionButton_OnClick): a hardware mouse press (isSecureAction, not isKeyPress) acts on
-- the up event; anything else acts on the down event when useOnKeyDown (attribute, else the ActionButtonUseKeyDown CVar) or
-- pressAndHoldAction says so, else on the up event. Returns true when it acted.
function M.click(w, frame, inputButton, down, isKeyPress, isSecureAction)
  local mousePress = not isKeyPress and isSecureAction
  local holdAction = SecureAttributes.attribute(w, frame, "pressAndHoldAction")
  local useDown = not mousePress and (M.shouldUseOnKeyDown(w, frame) or holdAction)
  if (down and useDown) or (not down and not useDown) then
    click(w, frame, inputButton, down, down and isKeyPress)
    return true
  elseif not down and (holdAction or query(w, "GetCVarBool", "ActionButtonUseKeyHeldSpell")) then
    local button, unit, actionType = convert(w, frame, inputButton, HOLD_RELEASE)
    perform(w, frame, button, unit, actionType, false)
    return true
  end
  return false
end

-- The OnClick script of SecureActionButtonTemplate. assumed (no source): the client passes isSecureAction for a hardware
-- click only, so secure execution stands for one here and a click from tainted code (Click()) is a key press.
function M.onClick(w, frame, button, down)
  return M.click(w, frame, button, down, false, Taint.current(w) == nil)
end

-- source: `:844-889` (SecureUnitButton_OnClick), minus the click-binding branch (C_ClickBindings is not modelled).
function M.unitButtonOnClick(w, frame, button, down)
  local actionType = modifiedAttribute(w, frame, "type", button)
  if (actionType == "menu" or actionType == "togglemenu") and query(w, "SpellIsTargeting") then
    call(w, "stop", "SpellStopTargeting")
    return
  end
  click(w, frame, button, down, false)
end

-- source: `:831-842` (SecureUnitButton_OnLoad): the defaults the template itself does not set.
function M.unitButtonOnLoad(_, frame, unit, menufunc, clickArgs)
  if clickArgs then
    frame:RegisterForClicks(unpack(clickArgs))
  else
    frame:RegisterForClicks("AnyUp")
  end
  frame:SetAttribute("*type1", "target")
  frame:SetAttribute("*type2", "menu")
  frame:SetAttribute("unit", unit)
  frame:SetAttribute("menu-function", menufunc)
end

function M.install(w)
  SecureAttributes.install(w)
  local function define(name, fn)
    w:install(name, function(...)
      return fn(w, ...)
    end, FRAMEXML)
  end
  define("SecureActionButton_ShouldUseOnKeyDown", M.shouldUseOnKeyDown)
  define("SecureActionButton_OnClick", M.click)
  define("SecureUnitButton_OnClick", M.unitButtonOnClick)
  define("SecureUnitButton_OnLoad", M.unitButtonOnLoad)
end

return M
