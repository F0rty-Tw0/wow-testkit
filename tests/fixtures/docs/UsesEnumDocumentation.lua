-- Synthetic fixture: values that only resolve once EnumDocumentation.lua has been collected.
local UsesEnum = {
  Name = "UsesEnum",
  EnumField = Enum.Foo.Bar,
  EnumSum = Enum.Foo.Bar + Enum.Foo.Baz,
  ConstantProduct = Constants.X.Y * 2,
  ChainedConstant = Constants.X.W,
  EnumTypedConstant = Constants.X.Q - 1,
  StringConstant = Constants.X.S,
  EnumMeta = Enum.FooMeta.NumValues,
}

APIDocumentation:AddDocumentationTable(UsesEnum)
