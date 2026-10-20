-- Synthetic fixture shaped like Ketho's WidgetAPI.lua: widget types with inherited types and method names.
local WidgetAPI = {
  Object = {
    inherits = {},
    methods = {
      "GetName",
    },
  },
  Frame = {
    inherits = { "Object" },
    methods = {
      "SetPoint",
      "Show",
    },
  },
}

return WidgetAPI
