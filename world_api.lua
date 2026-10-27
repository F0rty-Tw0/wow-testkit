-- Builds the installed function for a WoW API name: call counting and argument validation in addon context,
-- then a w:stub override, then the kit implementation (its arguments pass through w.revealArgs(name, packed) when one is set, its
-- results through w.returnFilter(name, signature, packed) when one is set and the caller is addon code), then
-- signature-derived defaults.
local M = {}

local Callsite = require("ui.callsite")
local Validate = require("validate")

local unpack = unpack
-- Localized: addon code may assign a global named select.
local select = select

local DEFAULT_BY_LUA = { number = 0, string = "", boolean = false }

local function pack(...)
  return { n = select("#", ...), ... }
end

local function defaultFor(spec, mayReturnNothing)
  if spec.nilable or mayReturnNothing then
    return nil
  end
  if spec.lua == "table" then
    return {}
  end
  return DEFAULT_BY_LUA[spec.lua]
end

-- Packed default returns for a manifest signature; nothing for a function without returns.
function M.defaults(signature)
  local returns = signature.returns or {}
  local out = { n = #returns }
  for i, spec in ipairs(returns) do
    out[i] = defaultFor(spec, signature.mayReturnNothing)
  end
  return out
end

local function argsKey(args)
  local parts = {}
  for i = 1, args.n do
    parts[i] = tostring(args[i])
  end
  return table.concat(parts, "|")
end

local function packList(values)
  return { n = table.maxn(values), unpack(values, 1, table.maxn(values)) }
end

-- Packed results of a w:stub override for these args, or nil when it does not match (fall through).
function M.resolve(stub, args)
  if type(stub) == "function" then
    return pack(stub(unpack(args, 1, args.n)))
  end
  local values = stub.returns or (stub.byArgs and stub.byArgs[argsKey(args)]) or stub.default
  return values and packList(values)
end

local function countCall(w, name, signature, args)
  w.calls[name] = (w.calls[name] or 0) + 1
  if not signature then
    return nil
  end
  return Validate.check(signature, args, w.realType, { name = name, flavor = w.flavor })
end

-- Records that a call to name was answered with defaults: w.unscripted lists what a scenario forgot to fake, and
-- w.dev.unscripted the same per addon for calls made in addon context.
function M.markUnscripted(w, name)
  w.unscripted[name] = (w.unscripted[name] or 0) + 1
  Callsite.credit(w, "unscripted", name)
end

local function unscripted(w, name, signature)
  local out = signature and M.defaults(signature) or { n = 0 }
  if not signature or out.n > 0 then
    M.markUnscripted(w, name)
  end
  return unpack(out, 1, out.n)
end

-- signature: manifest entry, or nil for a permissive-tier name; impl: kit implementation, or nil for a stub.
function M.wrap(w, name, signature, impl)
  return function(...)
    local args = pack(...)
    if w:callerIsAddon() then
      local message = countCall(w, name, signature, args)
      if message then
        error(message, 2)
      end
    end
    local stub = w.stubs[name]
    local values = stub and M.resolve(stub, args)
    if values then
      return unpack(values, 1, values.n)
    end
    if impl then
      local real = w.revealArgs and w.revealArgs(name, args) or args
      local filter = w.returnFilter
      if filter and w:callerIsAddon() then
        local packed = pack(impl(unpack(real, 1, real.n)))
        local filtered = filter(name, signature, packed)
        return unpack(filtered, 1, filtered.n)
      end
      return impl(unpack(real, 1, real.n))
    end
    return unscripted(w, name, signature)
  end
end

return M
