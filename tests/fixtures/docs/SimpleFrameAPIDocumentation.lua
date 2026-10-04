-- Synthetic fixture: a widget script object.
local SimpleFrameAPI = {
  Name = "SimpleFrameAPI",
  Type = "ScriptObject",
  Environment = "All",

  Functions = {
    {
      Name = "SetPoint",
      Type = "Function",
      IsProtectedFunction = true,

      Arguments = {
        { Name = "point", Type = "FramePoint", Nilable = false },
        { Name = "relativeTo", Type = "ScriptRegion", Nilable = true },
        { Name = "relativePoint", Type = "FramePoint", Nilable = true },
        { Name = "offsetX", Type = "uiUnit", Nilable = true },
        { Name = "offsetY", Type = "uiUnit", Nilable = true },
      },
    },
    {
      Name = "GetAnchorInfo",
      Type = "Function",
      ConstSecretAccessor = true,

      Returns = {
        { Name = "info", Type = "SimpleFrameAnchorInfo", Nilable = false },
      },
    },
  },

  Events = {},
  Tables = {
    {
      Name = "SimpleFrameAnchorInfo",
      Type = "Structure",
      Fields = {
        { Name = "point", Type = "FramePoint", Nilable = false },
      },
    },
  },
  Predicates = {},
}

APIDocumentation:AddDocumentationTable(SimpleFrameAPI)
