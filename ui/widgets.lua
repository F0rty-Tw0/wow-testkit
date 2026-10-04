-- CreateFrame and CreateFont. A widget is an empty table whose metatable's __index holds its type's methods;
-- its state lives in the weak-keyed w.ui.state. Method names come from Ketho's WidgetAPI for the flavor,
-- signatures from the Blizzard doc systems (ui/inherits.lua). Each method is the hand-written one from
-- ui/behaviour.lua, else the generic rule: SetX stores its args, GetX/IsX returns them (or the signature's
-- defaults, counted in w.unscripted["<Type>:<Method>"], when nothing was set), anything else is a counted no-op.
local M = {}

local Behaviour = require("ui.behaviour")
local Inherits = require("ui.inherits")
local Validate = require("validate")
local WorldApi = require("world_api")

local unpack = unpack

local NO_VALUES = { n = 0 }
local GETTER_PATTERNS = { "^Get(%u.*)$", "^Is(%u.*)$" }
local SETTER_PATTERN = "^Set(%u.*)$"

-- Per Ketho widget table (one per flavor): lowercase type -> type, and type -> plan. Plans are pure data.
local catalogs = setmetatable({}, { __mode = "k" })

local function pack(...)
  return { n = select("#", ...), ... }
end

local function catalogFor(w)
  local widgetTypes = w.globals.widgets
  local catalog = catalogs[widgetTypes]
  if not catalog then
    catalog = { types = {}, plans = {} }
    for typeName in pairs(widgetTypes) do
      catalog.types[typeName:lower()] = typeName
    end
    catalogs[widgetTypes] = catalog
  end
  return catalog
end

-- Every argument nilable: widget methods check only the non-nil args they are passed (no arity check).
local function lenient(signature)
  local args = {}
  for i, spec in ipairs(signature.args or {}) do
    args[i] = { name = spec.name, lua = spec.lua, nilable = true }
  end
  return { args = args }
end

local function findSignature(manifest, ancestors, name)
  for _, ancestor in ipairs(ancestors) do
    for _, system in ipairs(Inherits.docSystemsFor(ancestor)) do
      local doc = manifest.widgets[system]
      local signature = doc and doc.methods and doc.methods[name]
      if signature then
        return signature
      end
    end
  end
  return nil
end

local function buildPlan(w, typeName)
  local ancestors = Inherits.ancestors(w.globals.widgets, typeName)
  local isA, methods = {}, {}
  for _, ancestor in ipairs(ancestors) do
    isA[ancestor:lower()] = true
  end
  for name in pairs(Inherits.methodNames(w.globals.widgets, typeName)) do
    local signature = findSignature(w.manifest, ancestors, name)
    methods[name] = { signature = signature, check = signature and lenient(signature) }
  end
  return { type = typeName, isA = isA, isFrame = isA.frame == true, methods = methods }
end

local function planFor(w, typeName)
  local plans = catalogFor(w).plans
  plans[typeName] = plans[typeName] or buildPlan(w, typeName)
  return plans[typeName]
end

local function generic(plan, name, signature)
  local key = name:match(SETTER_PATTERN)
  if key then
    return function(_, _, st, ...)
      st.values[key] = pack(...)
    end
  end
  local label = plan.type .. ":" .. name
  for _, pattern in ipairs(GETTER_PATTERNS) do
    key = name:match(pattern)
    if key then
      return function(w, _, st)
        local values = st.values[key]
        if not values then
          WorldApi.markUnscripted(w, label)
          values = signature and WorldApi.defaults(signature) or NO_VALUES
        end
        return unpack(values, 1, values.n)
      end
    end
  end
  return function(w)
    WorldApi.markUnscripted(w, label)
  end
end

-- The installed method: resolves self's state, checks args in addon context, then runs impl(w, self, st, ...).
local function bind(w, plan, name, impl, check)
  local label = plan.type .. ":" .. name
  local names = { name = label, flavor = w.flavor }
  return function(self, ...)
    local st = w.ui.state[self]
    if not st then
      error(label .. ": self is not a widget of this world", 2)
    end
    if check and w:callerIsAddon() then
      local message = Validate.check(check, pack(...), w.realType, names)
      if message then
        error(message, 2)
      end
    end
    return impl(w, self, st, ...)
  end
end

local function classFor(w, typeName)
  local class = w.ui.classes[typeName]
  if not class then
    local plan = planFor(w, typeName)
    local methods = {}
    for name, entry in pairs(plan.methods) do
      local impl = Behaviour.methods[name] or generic(plan, name, entry.signature)
      methods[name] = bind(w, plan, name, impl, entry.check)
    end
    class = { plan = plan, meta = { __index = methods } }
    w.ui.classes[typeName] = class
  end
  return class
end

-- Creates a typeName widget (a Ketho type name, exact case) under parent; a name registers _G[name].
local function create(w, typeName, name, parent)
  local class = classFor(w, typeName)
  local obj = setmetatable({}, class.meta)
  local st = { plan = class.plan, name = name, shown = true, points = {}, values = {}, children = {}, regions = {} }
  w.ui.state[obj] = st
  Behaviour.setParent(w, obj, st, parent)
  if name ~= nil then
    w:setGlobal(name, obj)
  end
  return obj
end

-- applyTemplates(w, frame, templates): Task 12 fills this in (XML templates); CreateFrame passes its template
-- argument through. Default: no-op.
function M.applyTemplates() end

local function createFrame(w)
  return function(frameType, name, parent, template)
    local typeName = type(frameType) == "string" and catalogFor(w).types[frameType:lower()]
    if not typeName or not planFor(w, typeName).isFrame then
      error(string.format("CreateFrame: unknown frame type '%s' on %s", tostring(frameType), w.flavor), 2)
    end
    local frame = create(w, typeName, name, parent)
    M.applyTemplates(w, frame, template)
    return frame
  end
end

function M.install(w)
  w.ui = {
    state = setmetatable({}, { __mode = "k" }),
    classes = {},
    create = function(typeName, name, parent)
      return create(w, typeName, name, parent)
    end,
  }
  w:install("CreateFrame", createFrame(w), { gate = "none" })
  w:install("CreateFont", function(name)
    return create(w, "Font", name, nil)
  end, { gate = "api" })
end

return M
