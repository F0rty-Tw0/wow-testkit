-- Synthetic fixture: a constant defined in terms of itself never settles.
local Loop = {
  Tables = {
    {
      Name = "Loop",
      Type = "Constants",
      Values = {
        { Name = "N", Type = "number", Value = Constants.Loop.N + 1 },
      },
    },
  },
}

APIDocumentation:AddDocumentationTable(Loop)
