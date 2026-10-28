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

-- Layout maths writes fractions such as 1/3 of a pixel: 14 significant digits survive, not %g's default six.
local function test_numbers_keep_fourteen_significant_digits()
  A.eq(Json.encode(1 / 3), "0.33333333333333")
  A.eq(Json.encode(1234.5678901234), "1234.5678901234")
end

local function test_escapes_strings()
  A.eq(Json.encode('a"b\\c\n\1'), '"a\\"b\\\\c\\n\\u0001"')
end

local FFFD = string.char(239, 191, 189)

-- JSON text is UTF-8: a byte sequence that is not (a stray 0xbb in an error message) becomes U+FFFD (bytes EF BF BD),
-- one per bad byte.
local function test_invalid_utf8_becomes_replacement_characters()
  A.eq(Json.encode("a\187b"), '"a' .. FFFD .. 'b"')
  A.eq(Json.encode("\226\130"), '"' .. FFFD:rep(2) .. '"') -- a cut-off 3-byte sequence
  A.eq(Json.encode("\192\128\237\160\128"), '"' .. FFFD:rep(5) .. '"') -- overlong NUL, surrogate
  A.eq(Json.encode({ ["k\255"] = 1 }), '{"k' .. FFFD .. '":1}')
end

local function test_valid_utf8_passes_through()
  local text = "caf\195\169 \226\130\172 \240\159\152\128"
  A.eq(Json.encode(text), '"' .. text .. '"')
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
  test_numbers_keep_fourteen_significant_digits()
  test_escapes_strings()
  test_invalid_utf8_becomes_replacement_characters()
  test_valid_utf8_passes_through()
  test_indent_option()
  test_null_encodes_as_json_null_inside_lists_and_objects()
  test_rejects_what_json_cannot_hold()
end
