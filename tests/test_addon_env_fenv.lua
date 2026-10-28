-- The fenv helpers live in their own module so addon_env.lua stays under the 300-line cap.
local A = require("assert")
local Fenv = require("addon_env_fenv")

local function test_the_module_exports_the_helpers_addon_env_uses()
  local overrides = {}
  Fenv.addSetfenv(overrides, {})
  A.same({ type(Fenv.call), type(overrides.setfenv) }, { "function", "function" })
end

return function()
  test_the_module_exports_the_helpers_addon_env_uses()
end
