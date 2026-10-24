-- JSON encoder: json.lua.
local A = require("assert")
local Json = require("json")

local function test_encodes_scalars_arrays_and_sorted_objects()
  A.eq(Json.encode({ a = 1, b = { 1, 2, 3 }, c = "x" }), '{"a":1,"b":[1,2,3],"c":"x"}')
  A.eq(Json.encode({}), "[]")
  A.eq(Json.encode(Json.object({})), "{}")
  A.eq(Json.encode(0.5), "0.5")
  A.eq(Json.encode(true), "true")
  A.eq(Json.encode(nil), "null")
end

local function test_escapes_strings()
  A.eq(Json.encode('a"b\\c\n\1'), '"a\\"b\\\\c\\n\\u0001"')
end

local function test_indent_option()
  A.eq(Json.encode({ a = { 1 } }, 2), '{\n  "a": [\n    1\n  ]\n}')
end

local function test_null_encodes_as_json_null_inside_lists_and_objects()
  A.eq(Json.encode({ 1, Json.null, 3 }), "[1,null,3]")
  A.eq(Json.encode({ a = Json.null }), '{"a":null}')
end

local function test_rejects_what_json_cannot_hold()
  A.errors(function()
    Json.encode(0 / 0)
  end, "non-finite")
  A.errors(function()
    Json.encode({ 1, x = 2 })
  end, "mixed")
  A.errors(function()
    Json.encode(print)
  end, "function")
end

return function()
  test_encodes_scalars_arrays_and_sorted_objects()
  test_escapes_strings()
  test_indent_option()
  test_null_encodes_as_json_null_inside_lists_and_objects()
  test_rejects_what_json_cannot_hold()
end
