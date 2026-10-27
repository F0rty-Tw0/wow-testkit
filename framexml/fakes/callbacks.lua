-- CallbackRegistryMixin and the global EventRegistry built from it. Kit-authored bodies over row W72: register, trigger
-- and unregister keyed by owner, the event table GenerateCallbackEvents fills, and the argument and event checks the
-- client's registry raises. EventRegistry's frame-event helpers (RegisterFrameEventAndCallback and friends) are not
-- modelled.
local M = {}

local Core = require("framexml.fakes.core")

-- Localized: addon code may assign globals named error, ipairs, pairs, select, type or unpack.
local error, ipairs, pairs, select, type, unpack = error, ipairs, pairs, select, type, unpack
local remove = table.remove

local FIRST_OWNER_ID = 0

local function pack(...)
  return { n = select("#", ...), ... }
end

-- source: row W72 (confirmed) blizzard_sharedxmlbase/callbackregistry.lua:112 the entry of an owner under an event,
-- nil when the owner has none. Entries keep registration order; the client's order is unspecified.
local function indexOf(entries, owner)
  for index, entry in ipairs(entries) do
    if entry.owner == owner then
      return index
    end
  end

  return nil
end

local methods = {}

function methods:OnLoad()
  self.callbacks = {}
  self.nextOwnerId = FIRST_OWNER_ID
end

function methods:SetUndefinedEventsAllowed(allowed)
  self.isUndefinedEventAllowed = allowed
end

function methods:GenerateCallbackEvents(eventTable)
  self.Event = self.Event or {}
  if type(eventTable) ~= "table" then
    error("CallbackRegistryMixin:GenerateCallbackEvents 'eventTable' requires table type.", 2)
  end
  for _, name in ipairs(eventTable) do
    if self.Event[name] then
      error(("CallbackRegistryMixin:GenerateCallbackEvents: event '%s' already exists."):format(name), 2)
    end
    self.Event[name] = name
  end
end

function methods:UnregisterCallback(event, owner)
  if type(event) ~= "string" then
    error("CallbackRegistryMixin:UnregisterCallback 'event' requires string type.", 2)
  elseif owner == nil then
    error("CallbackRegistryMixin:UnregisterCallback 'owner' is required.", 2)
  end
  local entries = self.callbacks[event]
  local index = entries and indexOf(entries, owner)
  if index then
    remove(entries, index)
  end
end

-- An owner of nil gets a counter number, which is why a number from the caller is refused. Extra arguments are kept and
-- come after the owner on every call.
function methods:RegisterCallback(event, func, owner, ...)
  if type(event) ~= "string" then
    error("CallbackRegistryMixin::RegisterCallback 'event' requires string type.", 2)
  elseif type(func) ~= "function" then
    error("CallbackRegistryMixin::RegisterCallback 'func' requires function type.", 2)
  elseif type(owner) == "number" then
    error("CallbackRegistryMixin:RegisterCallback 'owner' as number is reserved internally.", 2)
  end
  if owner == nil then
    self.nextOwnerId = self.nextOwnerId + 1
    owner = self.nextOwnerId
  end
  self:UnregisterCallback(event, owner)
  local entries = self.callbacks[event] or {}
  self.callbacks[event] = entries
  entries[#entries + 1] = { owner = owner, func = func, extra = pack(...) }

  return owner
end

function methods:RegisterCallbackWithHandle(event, func, owner, ...)
  owner = self:RegisterCallback(event, func, owner, ...)

  return {
    Unregister = function()
      self:UnregisterCallback(event, owner)
    end,
  }
end

function methods:HasRegistrantsForEvent(event)
  local entries = self.callbacks[event]

  return entries ~= nil and #entries > 0
end

-- The owner, the arguments given at registration, then the trigger's: one list, as a plain call would pass them.
local function joined(entry, triggered)
  local args = { entry.owner }
  for i = 1, entry.extra.n do
    args[i + 1] = entry.extra[i]
  end
  for i = 1, triggered.n do
    args[entry.extra.n + 1 + i] = triggered[i]
  end

  return args
end

-- source: row W72 (confirmed) an undefined event errors unless undefined events are allowed; a callback is called as
-- func(owner, ...). Each call goes through the world's try, so a failing callback reaches the error handler and the next
-- one still runs (assumed: the client calls them with securecallfunction). The registrants are copied first, so a callback
-- registered meanwhile waits for the next trigger.
local function triggerEvent(w)
  return function(self, event, ...)
    if type(event) ~= "string" then
      error("CallbackRegistryMixin:TriggerEvent 'event' requires string type.", 2)
    elseif not self.isUndefinedEventAllowed and not (self.Event and self.Event[event]) then
      error(("CallbackRegistryMixin:TriggerEvent event '%s' doesn't exist."):format(event), 2)
    end
    local entries = self.callbacks[event]
    if not entries then
      return
    end
    local snapshot = pack(unpack(entries))
    local triggered = pack(...)
    for i = 1, snapshot.n do
      local entry = snapshot[i]
      w:try(entry.func, unpack(joined(entry, triggered), 1, entry.extra.n + triggered.n + 1))
    end
  end
end

local function copyInto(object, source)
  for key, value in pairs(source) do
    object[key] = value
  end

  return object
end

function M.install(w)
  local mixin = copyInto({}, methods)
  mixin.TriggerEvent = triggerEvent(w)
  w:install("CallbackRegistryMixin", mixin, Core.GATE)
  local registry = copyInto({}, mixin)
  registry:OnLoad()
  registry:SetUndefinedEventsAllowed(true)
  w:install("EventRegistry", registry, Core.GATE)
end

return M
