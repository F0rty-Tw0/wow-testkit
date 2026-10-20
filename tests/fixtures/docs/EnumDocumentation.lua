-- Synthetic fixture: an enumeration plus constants that reference each other and the enumeration.
local EnumDoc = {
  Tables = {
    {
      Name = "Foo",
      Type = "Enumeration",
      NumValues = 2,
      MinValue = 1,
      MaxValue = 2,
      Fields = {
        { Name = "Bar", Type = "Foo", EnumValue = 1 },
        { Name = "Baz", Type = "Foo", EnumValue = 2 },
      },
    },
    {
      Name = "X",
      Type = "Constants",
      Values = {
        { Name = "Y", Type = "number", Value = 10 },
        { Name = "Z", Type = "number", Value = Constants.X.Y + 5 },
        { Name = "W", Type = "number", Value = Constants.X.Z + 1 },
        { Name = "Q", Type = "Foo", Value = "Bar" },
        { Name = "S", Type = "cstring", Value = "XVV" },
      },
    },
  },
  Predicates = {},
}

APIDocumentation:AddDocumentationTable(EnumDoc)
