-- CreateFrame and CreateFont. A widget is an empty table whose metatable's __index holds its type's methods;
-- its state lives in the weak-keyed w.ui.state. Method names come from Ketho's WidgetAPI for the flavor,
-- signatures from the Blizzard doc systems (ui/inherits.lua). Each method is the hand-written one from
-- ui/behaviour.lua, else the generic rule: SetX stores its args, GetX/IsX returns them (or the signature's
-- defaults, counted in w.unscripted["<Type>:<Method>"], when nothing was set), anything else is a counted no-op.
local M = {}

local Behaviour = require("ui.behaviour")
local Callsite = require("ui.callsite")
local Inherits = require("ui.inherits")
local Layout = require("ui.layout")
local ProtectedData = require("taint_protected_data")
local TemplateApply = require("ui.template_apply")
local Validate = require("validate")
local WorldApi = require("world_api")

local unpack = unpack
-- Localized: addon code may assign a global named select.
local select = select

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

-- Every argument nilable, checked only when passed (no arity check); one in unchecked takes any value.
local function lenient(signature, unchecked)
  local args = {}
  for i, spec in ipairs(signature.args or {}) do
    args[i] = { name = spec.name, lua = unchecked[spec.name] and "any" or spec.lua, nilable = true }
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
  local isFrame = isA.frame == true
  for name in pairs(Inherits.methodNames(w.globals.widgets, typeName)) do
    local signature = findSignature(w.manifest, ancestors, name)
    local unchecked = Behaviour.uncheckedArgs[name] or {}
    -- protected: a tainted call to it on a protected frame in combat is refused (row TS9); frames only, so Texture:Show() is not
    local protected = isFrame and ((signature and signature.protected) or ProtectedData.methods[name]) == true
    methods[name] = { signature = signature, check = signature and lenient(signature, unchecked), protected = protected }
  end
  return { type = typeName, isA = isA, isFrame = isFrame, methods = methods }
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
local function bind(w, plan, name, impl, check, protected)
  local label = plan.type .. ":" .. name
  local names = { name = label, flavor = w.flavor }
  local changesLayout = Layout.MUTATORS[name]
  return function(self, ...)
    local st = w.ui.state[self]
    if not st then
      error(label .. ": self is not a widget of this world", 2)
    end
    -- Cheapest test first: forbidden frames and flagged methods in combat go on to the taint guard, which checks the caller.
    if (st.forbidden or (protected and w.mock and w.mock.combat == true)) and w.taint.guardMethod(w, self, plan.type, name) then
      return
    end
    if changesLayout then
      Layout.invalidate(w, self)
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
      methods[name] = bind(w, plan, name, entry.impl or implFor(plan, name, entry.signature), entry.check, entry.protected)
    end
    class = { plan = plan, meta = { __index = methods } }
    w.ui.classes[typeName] = class
  end
  return class
end

-- Creates a typeName widget (a Ketho type name, exact case) under parent; a name registers _G[name] as one key,
-- dots included (never a namespace path).
local function create(w, typeName, name, parent)
  local class = classFor(w, typeName)
  local obj = setmetatable({}, class.meta)
  w.ui.seq = w.ui.seq + 1
  local st = { plan = class.plan, seq = w.ui.seq, name = name, shown = true, points = {}, values = {}, children = {}, regions = {} }
  w.ui.state[obj] = st
  w.ui.bySeq[st.seq] = obj
  Callsite.credit(w, "widgets", typeName)
  Behaviour.setParent(w, obj, st, parent)
  if name ~= nil then
    w:rawWrite(_G, name, obj)
  end
  if class.plan.init then
    class.plan.init(w, obj, st)
  end
  return obj
end

-- The template list (ui/template_apply.lua), then the templates' OnLoad: it runs once the frame is built, before
-- CreateFrame returns.
function M.applyTemplates(w, frame, templates)
  TemplateApply.applyList(w, frame, templates)
  if type(templates) == "string" and w:getScript(frame, "OnLoad") then
    w:callScript(frame, "OnLoad")
  end
end

-- True when frame is protected, explicitly (a Secure* template) or implicitly (taint_frames.lua).
function M.isProtected(w, frame)
  return (w.taint.isProtected(w, frame))
end

-- The exact frame type name for a CreateFrame argument: a registered intrinsic first, else the flavor's catalog. nil
-- for a non-string and for a type that is not a frame.
function M.resolveType(w, frameType)
  local lower = type(frameType) == "string" and frameType:lower()
  local typeName = catalogFor(w).types[lower]
  for name in pairs(w.ui.intrinsics) do
    if name:lower() == lower then
      typeName = name
    end
  end
  return typeName and planFor(w, typeName).isFrame and typeName or nil
end

-- Creates a frame of frameType (any case) under parent, with no templates.
function M.newFrame(w, frameType, name, parent)
  local typeName = M.resolveType(w, frameType)
  if not typeName then
    error(string.format("CreateFrame: unknown frame type '%s' on %s", tostring(frameType), w.flavor), Callsite.level())
  end
  return create(w, typeName, name, parent)
end

local function createFrame(w)
  return function(frameType, name, parent, template)
    local frame = M.newFrame(w, frameType, name, parent)
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
    -- name -> { type, apply(w, obj, st) }, the XML virtual templates (ui/xml_build.lua registers them)
    virtuals = {},
    seq = 0,
    -- seq -> widget, weak-valued: EnumerateFrames walks it in creation order
    bySeq = setmetatable({}, { __mode = "v" }),
    create = function(typeName, name, parent)
      return create(w, typeName, name, parent)
    end,
  }
  w.input = { mouseFocus = nil, editFocus = nil }
  Layout.install(w)
  w:install("CreateFrame", createFrame(w), { gate = "none" })
  w:install("CreateFont", function(name)
    return create(w, "Font", name, nil)
  end, { gate = "api" })
end

return M
