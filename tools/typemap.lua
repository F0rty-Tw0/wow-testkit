-- Maps Blizzard API doc types ("bool", "cstring", "ItemQuality", ...) to the Lua type a value of that type has.
local M = {}

-- Doc types starting with one of these are strings: UnitToken, UnitTokenVariant, kstringClubId, ...
local STRING_PREFIXES = { "UnitToken", "kstring" }

local DIRECT = {
  bool = "boolean",
  ["function"] = "function",
  luaFunction = "function",
  table = "table",
  colorRGB = "table",
  colorRGBA = "table",
  vector2 = "table",
  vector3 = "table",
  LuaValueReference = "any",
  LuaValueVariant = "any",
}

local NUMBER_TYPES = {
  "number",
  "luaIndex",
  "time_t",
  "BigInteger",
  "BigUInteger",
  "fileID",
  "uiMapID",
  "size",
  "SingleColorValue",
  "uiUnit",
  "uiFontHeight",
  "normalizedValue",
  "DurationSeconds",
  "DurationSecondsDouble",
  "DurationSecondsPrimitive",
  "DurationMillisecondsPrimitive",
  "FrameTime",
  "WOWMONEY",
}

local STRING_TYPES = {
  "string",
  "cstring",
  "textureAtlas",
  "textureKit",
  "WOWGUID",
  "stringView",
  "mouseButton",
}

for _, name in ipairs(NUMBER_TYPES) do
  DIRECT[name] = "number"
end
for _, name in ipairs(STRING_TYPES) do
  DIRECT[name] = "string"
end

-- known = { enums = set, structs = set, callbacks = set } built from the docs being processed.
-- An unknown type maps to "any" and is recorded in report.unknownTypes.
function M.luaType(docType, known, report)
  local direct = DIRECT[docType]
  if direct then
    return direct
  end
  for _, prefix in ipairs(STRING_PREFIXES) do
    if docType:sub(1, #prefix) == prefix then
      return "string"
    end
  end
  if known.enums[docType] then
    return "number"
  end
  if known.structs[docType] then
    return "table"
  end
  if known.callbacks[docType] then
    return "function"
  end
  report.unknownTypes[docType] = true
  return "any"
end

return M
