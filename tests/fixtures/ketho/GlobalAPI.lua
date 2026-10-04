-- Synthetic fixture shaped like Ketho's GlobalAPI.lua: global API names, then Lua library names.
local GlobalAPI = {
  "C_SecureSystem.DoSecureThing",
  "GetTime",
  "UnitName",
}

local LuaAPI = {
  "abs",
  "string.format",
}

return { GlobalAPI, LuaAPI }
