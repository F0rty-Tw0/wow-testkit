-- CreateFrame and CreateFont. A widget is an empty table whose metatable's __index holds its type's methods;
-- its state lives in the weak-keyed w.ui.state. Method names come from Ketho's WidgetAPI for the flavor,
-- signatures from the Blizzard doc systems (ui/inherits.lua). Each method is the hand-written one from
-- ui/behaviour.lua, else the generic rule: SetX stores its args, GetX/IsX returns them (or the signature's
-- defaults, counted in w.unscripted["<Type>:<Method>"], when nothing was set), anything else is a counted no-op.
local M = {}

local Behaviour = require("ui.behaviour")
local Inherits = require("ui.inherits")
local Templates = require("ui.templates")
local Validate = require("validate")
local WorldApi = require("world_api")

local unpack = unpack

local NO_VALUES = { n = 0 }
local GETTER_PATTERNS = { "^Get(%u.*)$", "^Is(%u.*)$" }
local SETTER_PATTERN = "^Set(%u.*)$"
-- A template child whose type the flavor's Ketho WidgetAPI lacks is created as a plain frame.
local FALLBACK_CHILD_TYPE = "Frame"

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
  local intrinsic = w.ui.intrinsics[typeName]
  if intrinsic then
    return intrinsic.plan
  end
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

-- The method body for name on plan: a type-specific one (Behaviour.typed) wins over the name-keyed hand-written
-- one, which wins over the generic Set/Get/no-op rule.
local function implFor(plan, name, signature)
  local typed = Behaviour.typed[name]
  return (typed and typed(plan)) or Behaviour.methods[name] or generic(plan, name, signature)
end

local function classFor(w, typeName)
  local class = w.ui.classes[typeName]
  if not class then
    local plan = planFor(w, typeName)
    local methods = {}
    for name, entry in pairs(plan.methods) do
      methods[name] = bind(w, plan, name, entry.impl or implFor(plan, name, entry.signature), entry.check)
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
  if class.plan.init then
    class.plan.init(w, obj, st)
  end
  return obj
end

-- Copies a mixin table's fields onto frame, like the client's Mixin(frame, mixin).
local function copyMixin(frame, mixin)
  for key, value in pairs(mixin) do
    frame[key] = value
  end
end

local function applyTemplate(w, frame, st, entry)
  for _, child in ipairs(entry.children) do
    local childType = w.globals.widgets[child.type] and child.type or FALLBACK_CHILD_TYPE
    frame[child.key] = create(w, childType, nil, frame)
  end
  if entry.size then
    st.width, st.height = entry.size[1], entry.size[2]
  end
  st.protected = st.protected or entry.protected
  for _, name in ipairs(entry.mixins) do
    st.mixins[#st.mixins + 1] = name
    local mixin = rawget(_G, name)
    if type(mixin) == "table" then
      copyMixin(frame, mixin)
    end
  end
end

-- Applies a comma-separated template list in order (ui/templates.lua) when CreateFrame gets one. An unknown
-- template adds nothing and is counted in w.unscripted["template:<Name>"].
function M.applyTemplates(w, frame, templates)
  if type(templates) ~= "string" then
    return
  end
  local st = w.ui.state[frame]
  st.mixins = st.mixins or {}
  for name in templates:gmatch("[^,%s]+") do
    local entry = Templates.TEMPLATES[name]
    if entry then
      applyTemplate(w, frame, st, entry)
    else
      WorldApi.markUnscripted(w, "template:" .. name)
    end
  end
end

-- True when a Secure* template made frame protected.
function M.isProtected(w, frame)
  return w.ui.state[frame].protected == true
end

-- The exact type name for a CreateFrame argument: a registered intrinsic first, else the flavor's catalog.
local function resolveType(w, frameType)
  if type(frameType) ~= "string" then
    return nil
  end
  local lower = frameType:lower()
  for name in pairs(w.ui.intrinsics) do
    if name:lower() == lower then
      return name
    end
  end
  return catalogFor(w).types[lower]
end

local function createFrame(w)
  return function(frameType, name, parent, template)
    local typeName = resolveType(w, frameType)
    if not typeName or not planFor(w, typeName).isFrame then
      error(string.format("CreateFrame: unknown frame type '%s' on %s", tostring(frameType), w.flavor), 2)
    end
    local frame = create(w, typeName, name, parent)
    M.applyTemplates(w, frame, template)
    return frame
  end
end

-- The plan of an intrinsic type: base's plan copied (the catalog's stays untouched) with the intrinsic's own methods.
-- It keeps the base type as its type, as the client's GetObjectType does, and the name in plan.intrinsic. Two reserved
-- keys of methods are not methods: init, the once-per-frame hook, and scripts, handlers that run before the frame's own
-- (plan.intrinsicScripts, see World:callScript).
local function intrinsicPlan(base, name, baseType, methods)
  local isA, planMethods = {}, {}
  for key, value in pairs(base.isA) do
    isA[key] = value
  end
  isA[name:lower()] = true
  for key, entry in pairs(base.methods) do
    planMethods[key] = entry
  end
  local plan = { type = baseType, intrinsic = name, isA = isA, isFrame = base.isFrame, methods = planMethods }
  for key, value in pairs(methods) do
    if key == "init" then
      plan.init = value
    elseif key == "scripts" then
      plan.intrinsicScripts = value
    else
      planMethods[key] = { impl = value }
    end
  end
  return plan
end

-- Registers a widget type for this world only (the catalogs and plans are shared across worlds): methods are
-- fn(w, obj, st, ...) like ui/behaviour.lua, laid over baseType's. Registering a name again replaces it.
function M.registerIntrinsic(w, name, baseType, methods)
  if not w.globals.widgets[baseType] then
    error(string.format("registerIntrinsic: unknown base type '%s' on %s", tostring(baseType), w.flavor), 2)
  end
  if catalogFor(w).types[name:lower()] then
    error(string.format("registerIntrinsic: '%s' is already a widget type on %s", name, w.flavor), 2)
  end
  local plan = intrinsicPlan(planFor(w, baseType), name, baseType, methods)
  w.ui.intrinsics[name] = { baseType = baseType, methods = methods, plan = plan }
  w.ui.classes[name] = nil
end

function M.install(w)
  w.ui = {
    state = setmetatable({}, { __mode = "k" }),
    classes = {},
    intrinsics = {},
    create = function(typeName, name, parent)
      return create(w, typeName, name, parent)
    end,
  }
  w.input = { mouseFocus = nil, editFocus = nil }
  w:install("CreateFrame", createFrame(w), { gate = "none" })
  w:install("CreateFont", function(name)
    return create(w, "Font", name, nil)
  end, { gate = "api" })
end

return M
