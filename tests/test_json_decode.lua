-- JSON decoder: json.lua.
local A = require("assert")
local Json = require("json")

local function errorOf(text)
  local ok, err = pcall(Json.decode, text)
  A.eq(ok, false)
  return err
end

local function test_decodes_objects_and_arrays()
  A.same(Json.decode('{"a":1,"b":[true,false,"x"],"c":{"d":-2.5e1}}'), { a = 1, b = { true, false, "x" }, c = { d = -25 } })
end

local function test_nulls_become_json_null_and_count()
  local t = Json.decode("[1,null,null]")
  A.eq(#t, 3)
  A.eq(t[2], Json.null)
  A.eq(t[3], Json.null)
  A.eq(t.n, nil)
  A.eq(Json.decode('{"a":null}').a, Json.null)
  A.eq(Json.decode("null"), Json.null)
end

local function test_empty_object_and_array_round_trip()
  A.eq(Json.encode(Json.decode("{}")), "{}")
  A.eq(Json.encode(Json.decode("[]")), "[]")
  A.eq(Json.encode(Json.decode('{"a":{},"b":[]}')), '{"a":{},"b":[]}')
  A.eq(Json.encode(Json.decode('{"args":[1,null]}')), '{"args":[1,null]}')
end

local function test_string_escapes()
  A.eq(Json.decode('"a\\"b\\\\c\\/\\n\\t\\u0041\\u00e9\\ud83d\\ude00"'), 'a"b\\c/\n\tA' .. "\195\169" .. "\240\159\152\128")
end

local function test_numbers()
  A.eq(Json.decode("0"), 0)
  A.eq(Json.decode("-0.5"), -0.5)
  A.eq(Json.decode("1e3"), 1000)
  A.eq(Json.decode(" 12 "), 12)
  A.eq(pcall(Json.decode, "01"), false)
end

local function test_a_duplicated_key_keeps_the_last_value()
  A.eq(Json.decode('{"a":1,"a":2}').a, 2)
end

local function test_malformed_input_raises_with_offset()
  A.truthy(errorOf('{"a":1,}'):match("^json: .+ at 8$"))
  A.truthy(errorOf("[1 2]"):match("^json: .+ at 4$"))
  A.truthy(errorOf('"abc'):match("^json: .+ at 5$"))
  A.truthy(errorOf("1 x"):match("^json: .+ at 3$"))
  A.truthy(errorOf(""):match("^json: .+ at 1$"))
end

local function test_strings_reject_raw_controls_bad_escapes_and_lone_surrogates()
  A.truthy(errorOf('"a\nb"'):match("^json: .+ at 3$"))
  A.truthy(errorOf('"a\\xb"'):match("^json: .+ at 4$"))
  A.truthy(errorOf('"\\u12g4"'):match("^json: .+ at 6$"))
  A.truthy(errorOf('"\\ud83d"'):match("^json: .+ at 8$"))
  A.truthy(errorOf('"\\ude00"'):match("^json: .+ at 2$"))
end

local function test_deep_nesting_raises_instead_of_crashing()
  A.truthy(errorOf(string.rep("[", 100000)):match("^json: nested too deep at 1001$"))
  A.same(Json.decode("[1]"), { 1 })
end

return function()
  test_decodes_objects_and_arrays()
  test_nulls_become_json_null_and_count()
  test_empty_object_and_array_round_trip()
  test_string_escapes()
  test_numbers()
  test_a_duplicated_key_keeps_the_last_value()
  test_malformed_input_raises_with_offset()
  test_strings_reject_raw_controls_bad_escapes_and_lone_surrogates()
  test_deep_nesting_raises_instead_of_crashing()
end
