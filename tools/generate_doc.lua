-- One Blizzard API doc into a manifest part for tools/generate.lua: a system doc's functions, events, enums,
-- constants and structs, or a widget doc's methods. Counts the doc fields it does not carry in the report.
local M = {}

local Typemap = require("tools.typemap")

local SECURE_ONLY = "SecureOnly"
local META_FIELDS = { "NumValues", "MinValue", "MaxValue" }
local SECRET_PREFIXES = { "SecretWhen", "SecretIn" }
-- Doc fields not carried into the manifest; build() counts them in report.ignoredFields.
local IGNORED_FUNCTION_FIELDS = { "SecretReturnsForAspect", "SecretArgumentsAddAspect" }
local IGNORED_VALUE_FIELDS = { "InnerType", "Mixin" }

local function countIgnored(t, names, report)
  for _, name in ipairs(names) do
    if t[name] ~= nil then
      report.ignoredFields[name] = report.ignoredFields[name] + 1
    end
  end
end

local function field(f, ctx)
  countIgnored(f, IGNORED_VALUE_FIELDS, ctx.report)
  return {
    name = f.Name,
    type = f.Type,
    lua = Typemap.luaType(f.Type, ctx.known, ctx.report),
    nilable = f.Nilable == true,
    default = f.Default,
    neverSecret = f.NeverSecret or nil,
  }
end

local function fields(list, ctx)
  if not list or #list == 0 then
    return nil
  end
  local out = {}
  for i, f in ipairs(list) do
    out[i] = field(f, ctx)
  end
  return out
end

-- Sorted X of every `SecretWhen<X> = true` / `SecretIn<X> = true` flag, or nil.
local function secretConditions(t)
  local when = {}
  for key, value in pairs(t) do
    if value == true and type(key) == "string" then
      for _, prefix in ipairs(SECRET_PREFIXES) do
        when[#when + 1] = key:match("^" .. prefix .. "(%u.*)$")
      end
    end
  end
  if #when == 0 then
    return nil
  end
  table.sort(when)
  return when
end

local function secretInfo(fn)
  local when = secretConditions(fn)
  local returns = "never"
  if fn.SecretReturns == true then
    returns = "always"
  elseif when then
    returns = "when"
  end
  return { args = fn.SecretArguments, returns = returns, when = when, returnsNeverSecret = fn.ReturnsNeverSecret or nil }
end

local function isSecureOnly(fn, system)
  return fn.Environment == SECURE_ONLY or system.Environment == SECURE_ONLY
end

local function buildFunction(fn, system, ctx)
  countIgnored(fn, IGNORED_FUNCTION_FIELDS, ctx.report)
  local secureOnly = isSecureOnly(fn, system)
  return {
    args = fields(fn.Arguments, ctx),
    returns = fields(fn.Returns, ctx),
    mayReturnNothing = fn.MayReturnNothing or nil,
    secureOnly = secureOnly or nil,
    secret = secretInfo(fn),
  }
end

local function buildMethod(fn, system, ctx)
  local method = buildFunction(fn, system, ctx)
  method.protected = fn.IsProtectedFunction or nil
  method.constSecretAccessor = fn.ConstSecretAccessor or nil
  return method
end

local function buildEvent(ev, ctx)
  return {
    payload = fields(ev.Payload, ctx),
    secretWhen = secretConditions(ev),
    secretPayloads = ev.SecretPayloads or nil,
  }
end

local function addEnumeration(part, t, ctx)
  part.enums[t.Name] = ctx.known.enums[t.Name]
  local meta = {}
  for _, key in ipairs(META_FIELDS) do
    meta[key] = t[key]
  end
  if next(meta) then
    part.enums[t.Name .. "Meta"] = meta
  end
end

-- A string Value typed as a known enumeration becomes that enum's value, as the game resolves it.
local function addConstants(part, t, ctx)
  local values = {}
  for _, v in ipairs(t.Values or {}) do
    local enum = ctx.known.enums[v.Type]
    if type(v.Value) == "string" and enum then
      values[v.Name] = enum[v.Value]
    else
      values[v.Name] = v.Value
    end
  end
  part.constants[t.Name] = values
end

local function addStructure(part, t, ctx)
  part.structs[t.Name] = { fields = fields(t.Fields, ctx) or {} }
end

local TABLE_HANDLERS = { Enumeration = addEnumeration, Constants = addConstants, Structure = addStructure }

-- A function's own Namespace beats its system's; "" means a global (InCombatLockdown in C_RestrictedActions).
local function functionKey(fn, doc)
  local namespace = fn.Namespace or doc.Namespace
  return (namespace and namespace ~= "") and (namespace .. "." .. fn.Name) or fn.Name
end

-- The namespace of a key the flavor's client lacks: Ketho's GlobalAPI (the client's own name lists) has no function
-- in it, e.g. C_AuctionHouse on Classic Era. Secure-only functions stay: an addon-side list never shows them.
local function missingNamespace(key, fn, doc, ctx)
  local namespace = key:match("^(.+)%.[^.]+$")
  if namespace and not ctx.listed[namespace] and not isSecureOnly(fn, doc) then
    return namespace
  end
end

function M.addSystem(part, doc, ctx)
  for _, fn in ipairs(doc.Functions or {}) do
    local key = functionKey(fn, doc)
    local missing = missingNamespace(key, fn, doc, ctx)
    if missing then
      ctx.report.dropped[missing] = (ctx.report.dropped[missing] or 0) + 1
    else
      part.functions[key] = buildFunction(fn, doc, ctx)
    end
  end
  for _, ev in ipairs(doc.Events or {}) do
    part.events[ev.LiteralName] = buildEvent(ev, ctx)
  end
  for _, t in ipairs(doc.Tables or {}) do
    local handler = TABLE_HANDLERS[t.Type]
    if handler then
      handler(part, t, ctx)
    end
  end
end

-- Widget docs feed only `widgets`: their functions are methods and their Tables are not carried.
function M.addWidget(part, doc, ctx)
  local methods = {}
  for _, fn in ipairs(doc.Functions or {}) do
    methods[fn.Name] = buildMethod(fn, doc, ctx)
  end
  part.widgets[doc.Name] = { methods = methods }
end

function M.newReport()
  local report = { unknownTypes = {}, duplicates = {}, ignoredFields = {}, dropped = {} }
  for _, list in ipairs({ IGNORED_FUNCTION_FIELDS, IGNORED_VALUE_FIELDS }) do
    for _, name in ipairs(list) do
      report.ignoredFields[name] = 0
    end
  end
  return report
end

return M
