-- Synthetic fixture: a whole system restricted to secure code.
local SecureSystem = {
  Name = "SecureSystem",
  Type = "System",
  Namespace = "C_SecureSystem",
  Environment = "SecureOnly",

  Functions = {
    {
      Name = "DoSecureThing",
      Type = "Function",

      Returns = {
        { Name = "result", Type = "bool", Nilable = false },
      },
    },
  },

  Events = {},
  Tables = {},
  Predicates = {},
}

APIDocumentation:AddDocumentationTable(SecureSystem)
