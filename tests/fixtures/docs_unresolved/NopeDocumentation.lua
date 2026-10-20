-- Synthetic fixture: references a constant no doc defines (loaded as 0, reported) next to an enum that resolves.
local Nope = {
  Name = "Nope",
  Tables = {
    { Name = "Here", Type = "Enumeration", Fields = { { Name = "A", EnumValue = 1 } } },
  },
  Missing = Constants.Nope.X,
  Found = Enum.Here.A,
}

APIDocumentation:AddDocumentationTable(Nope)
