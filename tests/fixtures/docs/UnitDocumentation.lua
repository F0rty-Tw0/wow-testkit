-- Synthetic fixture shaped like a Blizzard_APIDocumentationGenerated system file.
local Unit = {
  Name = "Unit",
  Type = "System",
  Environment = "All",

  Functions = {
    {
      Name = "UnitName",
      Type = "Function",
      SecretWhenUnitNameIdentityRestricted = true,
      SecretArguments = "AllowedWhenTainted",

      Arguments = {
        { Name = "unit", Type = "UnitToken", Nilable = false },
      },

      Returns = {
        { Name = "name", Type = "cstring", Nilable = false },
        { Name = "realm", Type = "cstring", Nilable = true },
      },
    },
    {
      Name = "UnitHealth",
      Type = "Function",

      Arguments = {
        { Name = "unit", Type = "UnitToken", Nilable = false },
        { Name = "usePredicted", Type = "bool", Nilable = false, Default = true },
      },

      Returns = {
        { Name = "result", Type = "number", Nilable = false },
      },
    },
    {
      Name = "UnitExists",
      Type = "Function",

      Arguments = {
        { Name = "unit", Type = "UnitToken", Nilable = false },
      },

      Returns = {
        { Name = "result", Type = "bool", Nilable = false, NeverSecret = true },
      },
    },
    {
      Name = "UnitPosition",
      Type = "Function",
      MayReturnNothing = true,
      SecretReturns = true,

      Arguments = {
        { Name = "unit", Type = "UnitToken", Nilable = false },
      },

      Returns = {
        { Name = "positionX", Type = "number", Nilable = false },
        { Name = "positionY", Type = "number", Nilable = false },
      },
    },
    {
      Name = "UnitSetRole",
      Type = "Function",
      Environment = "SecureOnly",

      Arguments = {
        { Name = "unit", Type = "UnitToken", Nilable = false },
        { Name = "roleStr", Type = "cstring", Nilable = true },
      },
    },
    {
      Name = "UnitIsOwnerOrControllerOfUnit",
      Type = "Function",

      Arguments = {
        { Name = "controllingUnit", Type = "UnitToken", Nilable = false },
        { Name = "controlledUnit", Type = "UnitToken", Nilable = false },
        { Name = "includeVehicle", Type = "bool", Nilable = false, Default = false },
      },

      Returns = {
        { Name = "result", Type = "bool", Nilable = false },
      },
    },
    {
      Name = "UnitIsPlayer",
      Type = "Function",
      ReturnsNeverSecret = true,

      Arguments = {
        { Name = "unit", Type = "UnitToken", Nilable = false },
      },

      Returns = {
        { Name = "result", Type = "bool", Nilable = false },
      },
    },
  },

  Events = {
    {
      Name = "UnitHealth",
      Type = "Event",
      LiteralName = "UNIT_HEALTH",
      SynchronousEvent = true,
      SecretInChatMessagingLockdown = true,
      Payload = {
        { Name = "unitTarget", Type = "UnitTokenVariant", Nilable = false },
      },
    },
  },

  Tables = {
    {
      Name = "UnitSex",
      Type = "Enumeration",
      NumValues = 2,
      MinValue = 0,
      MaxValue = 1,
      Fields = {
        { Name = "Male", Type = "UnitSex", EnumValue = 0 },
        { Name = "Female", Type = "UnitSex", EnumValue = 1 },
      },
    },
    {
      Name = "UnitSexInfo",
      Type = "Structure",
      Fields = {
        { Name = "sex", Type = "UnitSex", Nilable = false },
      },
    },
  },
  Predicates = {},
}

APIDocumentation:AddDocumentationTable(Unit)
