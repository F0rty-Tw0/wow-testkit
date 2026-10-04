local A = require("assert")
local Serialize = require("serialize")

local KEY_COUNT = 12

local function test_dump_sorts_keys_and_inlines_scalar_arrays()
  A.eq(Serialize.dump({ b = 1, a = { 2, "x" } }), 'return {\n  a = { 2, "x" },\n  b = 1,\n}\n')
end

local function buildTable(first, last, step)
  local t = {}
  for i = first, last, step do
    t["key" .. i] = { n = i, list = { i, "v" .. i }, deep = { flag = i % 2 == 0 } }
  end
  return t
end

local function test_dump_is_identical_for_different_insertion_orders()
  local forward = buildTable(1, KEY_COUNT, 1)
  local backward = buildTable(KEY_COUNT, 1, -1)
  backward.extra = true
  backward.extra = nil
  A.eq(Serialize.dump(backward), Serialize.dump(forward))
end

local function test_dump_puts_number_keys_before_string_keys()
  A.eq(
    Serialize.dump({ [2] = "b", z = 1, [1] = "a", ["not-ident"] = 0, x = 3 }),
    'return {\n  [1] = "a",\n  [2] = "b",\n  ["not-ident"] = 0,\n  x = 3,\n  z = 1,\n}\n'
  )
end

local function test_dump_brackets_keyword_keys()
  A.eq(Serialize.dump({ ["end"] = 1 }), 'return {\n  ["end"] = 1,\n}\n')
end

local function test_dump_writes_integral_floats_without_fraction()
  A.eq(Serialize.dump({ 2.0, 3, -4.0, 0.5 }), "return { 2, 3, -4, 0.5 }\n")
end

local function test_dump_writes_non_integers_with_full_precision()
  A.eq(Serialize.dump(0.1), "return 0.10000000000000001\n")
end

local function test_dump_indents_nested_tables_and_arrays_of_tables()
  A.eq(Serialize.dump({ list = { { a = 1 }, 2 }, empty = {} }), "return {\n  empty = {},\n  list = {\n    {\n      a = 1,\n    },\n    2,\n  },\n}\n")
end

local function test_dump_errors_on_function()
  A.errors(function()
    Serialize.dump({ f = print })
  end, "function")
end

local function test_dump_errors_on_cycle()
  local t = {}
  t.self = t
  A.errors(function()
    Serialize.dump(t)
  end, "cycle")
end

local function test_dump_round_trips_through_loadstring()
  local value = { name = 'a\nb"c', list = { 1, 2.5, true }, nested = { [10] = "ten" } }
  local load = rawget(_G, "loadstring") or load
  A.same(load(Serialize.dump(value))(), value)
end

return function()
  test_dump_sorts_keys_and_inlines_scalar_arrays()
  test_dump_is_identical_for_different_insertion_orders()
  test_dump_puts_number_keys_before_string_keys()
  test_dump_brackets_keyword_keys()
  test_dump_writes_integral_floats_without_fraction()
  test_dump_writes_non_integers_with_full_precision()
  test_dump_indents_nested_tables_and_arrays_of_tables()
  test_dump_errors_on_function()
  test_dump_errors_on_cycle()
  test_dump_round_trips_through_loadstring()
end
