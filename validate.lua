-- Checks a call's arguments against a manifest function signature. Pure: no world state.
local M = {}

local ANY = "any"

-- Mirrors the C API's argument coercion: lua_tostring takes numbers, lua_tonumber takes numeric strings,
-- booleans are read as truthiness. Other expected types must match exactly.
local ACCEPTS = {
  string = function(got)
    return got == "string" or got == "number"
  end,
  number = function(got, value)
    return got == "number" or (got == "string" and tonumber(value) ~= nil)
  end,
  boolean = function(got)
    return got ~= "nil"
  end,
}

local function accepts(expected, got, value)
  local rule = ACCEPTS[expected]
  if rule then
    return rule(got, value)
  end
  return got == expected
end

local function isOptional(spec)
  return spec.nilable or spec.default ~= nil
end

-- signature: a manifest.functions entry; args: packed { n = count, ... }; realType: type-like function
-- (sees through secret values in later stages); names: { name = "UnitName", flavor = "retail" }.
-- Returns the error message for the first bad argument, or nil. Extra args beyond the signature are fine. An arg's
-- spec.also (ui/widgets.lua lenient) is true for any value, or one more Lua type taken as is (no coercion).
function M.check(signature, args, realType, names)
  for i, spec in ipairs(signature.args or {}) do
    local value = args[i]
    local skip = spec.lua == ANY or spec.also == true or (value == nil and isOptional(spec))
    local got = realType(value)
    if not skip and not accepts(spec.lua, got, value) and got ~= spec.also then
      return string.format("%s: bad argument #%d '%s' (%s expected, got %s) on %s", names.name, i, spec.name, spec.lua, got, names.flavor)
    end
  end
  return nil
end

return M
