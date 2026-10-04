local A = require("assert")
local Validate = require("validate")

local NAMES = { name = "UnitHealth", flavor = "retail" }

local function arg(name, lua, extra)
  local spec = { name = name, lua = lua, nilable = false }
  for k, v in pairs(extra or {}) do
    spec[k] = v
  end
  return spec
end

local function pack(...)
  return { n = select("#", ...), ... }
end

local function check(args, ...)
  return Validate.check({ args = args }, pack(...), type, NAMES)
end

local function test_matching_args_pass()
  A.eq(check({ arg("unit", "string") }, "player"), nil)
end

local function test_wrong_type_reports_name_index_arg_and_flavor()
  A.eq(check({ arg("unit", "string") }, {}), "UnitHealth: bad argument #1 'unit' (string expected, got table) on retail")
end

local function test_missing_required_arg_reports_got_nil()
  A.eq(check({ arg("unit", "string") }), "UnitHealth: bad argument #1 'unit' (string expected, got nil) on retail")
end

local function test_nilable_arg_is_optional()
  A.eq(check({ arg("unit", "string", { nilable = true }) }), nil)
end

local function test_false_default_makes_arg_optional()
  A.eq(check({ arg("unit", "string"), arg("usePredicted", "boolean", { default = false }) }, "player"), nil)
end

local function test_zero_default_makes_arg_optional()
  A.eq(check({ arg("index", "number", { default = 0 }) }), nil)
end

local function test_optional_arg_still_type_checked_when_given()
  local message = check({ arg("index", "number", { default = 0 }) }, "x")
  A.eq(message, "UnitHealth: bad argument #1 'index' (number expected, got string) on retail")
end

local function test_any_is_unchecked()
  A.eq(check({ arg("value", "any") }, {}), nil)
  A.eq(check({ arg("value", "any") }), nil)
end

local function test_extra_args_are_not_errors()
  A.eq(check({ arg("unit", "string") }, "player", 1, true), nil)
end

local function test_no_args_signature_accepts_anything()
  A.eq(Validate.check({}, pack("x"), type, NAMES), nil)
end

local function test_real_type_decides_the_type()
  local function realType()
    return "number"
  end
  A.eq(Validate.check({ args = { arg("index", "number") } }, pack({}), realType, NAMES), nil)
end

local function test_string_arg_accepts_number()
  A.eq(check({ arg("unit", "string") }, 1), nil)
end

local function test_number_arg_accepts_numeric_string()
  A.eq(check({ arg("index", "number") }, "12"), nil)
end

local function test_number_arg_rejects_non_numeric_string()
  A.eq(check({ arg("index", "number") }, "abc"), "UnitHealth: bad argument #1 'index' (number expected, got string) on retail")
end

local function test_number_arg_rejects_table()
  A.eq(check({ arg("index", "number") }, {}), "UnitHealth: bad argument #1 'index' (number expected, got table) on retail")
end

local function test_boolean_arg_accepts_any_non_nil_value()
  for _, value in ipairs({ true, 0, "x", {}, print }) do
    A.eq(check({ arg("flag", "boolean") }, value), nil)
  end
end

local function test_table_arg_rejects_string()
  A.eq(check({ arg("info", "table") }, "x"), "UnitHealth: bad argument #1 'info' (table expected, got string) on retail")
end

return function()
  test_matching_args_pass()
  test_wrong_type_reports_name_index_arg_and_flavor()
  test_missing_required_arg_reports_got_nil()
  test_nilable_arg_is_optional()
  test_false_default_makes_arg_optional()
  test_zero_default_makes_arg_optional()
  test_optional_arg_still_type_checked_when_given()
  test_any_is_unchecked()
  test_extra_args_are_not_errors()
  test_no_args_signature_accepts_anything()
  test_real_type_decides_the_type()
  test_string_arg_accepts_number()
  test_number_arg_accepts_numeric_string()
  test_number_arg_rejects_non_numeric_string()
  test_number_arg_rejects_table()
  test_boolean_arg_accepts_any_non_nil_value()
  test_table_arg_rejects_string()
end
