local A = require("assert")
local Typemap = require("tools.typemap")

local KNOWN = {
  enums = { ItemQuality = true },
  structs = { ItemInfo = true },
  callbacks = { DoneCallback = true },
}

local function map(docType)
  local report = { unknownTypes = {} }
  return Typemap.luaType(docType, KNOWN, report), report
end

local function test_bool_maps_to_boolean()
  A.eq(map("bool"), "boolean")
end

local function test_number_aliases_map_to_number()
  A.eq(map("luaIndex"), "number")
  A.eq(map("BigUInteger"), "number")
  A.eq(map("WOWMONEY"), "number")
end

local function test_string_aliases_map_to_string()
  A.eq(map("cstring"), "string")
  A.eq(map("WOWGUID"), "string")
end

local function test_unit_token_prefixed_types_map_to_string()
  A.eq(map("UnitTokenVariant"), "string")
end

local function test_kstring_prefixed_types_map_to_string()
  A.eq(map("kstringClubMessage"), "string")
end

local function test_mixin_value_types_map_to_table()
  A.eq(map("colorRGBA"), "table")
  A.eq(map("vector2"), "table")
end

local function test_lua_function_maps_to_function()
  A.eq(map("luaFunction"), "function")
end

local function test_known_enum_maps_to_number()
  A.eq(map("ItemQuality"), "number")
end

local function test_known_struct_maps_to_table()
  A.eq(map("ItemInfo"), "table")
end

local function test_callback_type_maps_to_function()
  A.eq(map("DoneCallback"), "function")
end

local function test_lua_value_variant_maps_to_any_without_report()
  local luaType, report = map("LuaValueVariant")
  A.eq(luaType, "any")
  A.same(report.unknownTypes, {})
end

local function test_unknown_type_maps_to_any_and_is_reported()
  local luaType, report = map("Mystery")
  A.eq(luaType, "any")
  A.same(report.unknownTypes, { Mystery = true })
end

return function()
  test_bool_maps_to_boolean()
  test_number_aliases_map_to_number()
  test_string_aliases_map_to_string()
  test_unit_token_prefixed_types_map_to_string()
  test_known_enum_maps_to_number()
  test_known_struct_maps_to_table()
  test_callback_type_maps_to_function()
  test_lua_value_variant_maps_to_any_without_report()
  test_unknown_type_maps_to_any_and_is_reported()
end
