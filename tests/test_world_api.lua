-- Installed API function behavior: validation and counting in addon context, w:stub overrides, defaults.
local A = require("assert")
local H = require("tests.helpers.world")

local withWorld = H.withWorld
-- Documented on retail (signature) but only in vanilla's globals.api (permissive tier, no signature).
local DOCUMENTED_ON_RETAIL_ONLY = "UnitEffectiveLevel"

local function test_addon_context_validates_args()
  withWorld("retail", function(w)
    local message = A.errors(function()
      w:run("addon", _G.UnitName, nil)
    end, "UnitName")
    A.contains(message, "unit")
  end)
end

local function test_scenario_context_skips_validation()
  withWorld("retail", function(w)
    w:run("scenario", _G.UnitName, nil)
  end)
end

local function test_defaulted_arg_is_optional()
  withWorld("retail", function(w)
    w:run("addon", _G.UnitHealth, "player")
  end)
end

local function test_addon_number_for_string_arg_is_coerced()
  withWorld("retail", function(w)
    w:run("addon", _G.UnitName, 1)
  end)
end

local function test_calls_counted_through_lua_function_and_pcall()
  withWorld("retail", function(w)
    local function f(u)
      return _G.UnitName(u)
    end
    w:run("addon", f, "player")
    w:run("addon", pcall, _G.UnitName, "player")
    A.eq(w.calls.UnitName, 2)
  end)
end

local function test_calls_not_counted_outside_addon_context()
  withWorld("retail", function(w)
    _G.UnitName("player")
    w:run("blizzard", _G.UnitName, "player")
    A.eq(w.calls.UnitName, nil)
  end)
end

local function test_documented_name_validated_on_retail_only()
  withWorld("retail", function(w)
    A.errors(function()
      w:run("addon", _G[DOCUMENTED_ON_RETAIL_ONLY], nil)
    end, DOCUMENTED_ON_RETAIL_ONLY)
  end)
  withWorld("vanilla", function(w)
    A.eq(select("#", w:run("addon", _G[DOCUMENTED_ON_RETAIL_ONLY], nil)), 0)
    A.eq(w.calls[DOCUMENTED_ON_RETAIL_ONLY], 1)
    A.eq(w.unscripted[DOCUMENTED_ON_RETAIL_ONLY], 1)
  end)
end

local function test_stub_by_args_and_default()
  withWorld("retail", function(w)
    w:stub("UnitName", { byArgs = { mouseover = { "Bob", "Realm" } }, default = { "X" } })
    A.same({ _G.UnitName("mouseover") }, { "Bob", "Realm" })
    A.same({ _G.UnitName("target") }, { "X" })
  end)
end

local function test_stub_by_args_joins_multiple_args()
  withWorld("retail", function(w)
    w:stub("UnitName", { byArgs = { ["player|1"] = { "Two" } } })
    A.eq(_G.UnitName("player", 1), "Two")
  end)
end

local function test_stub_unmatched_without_default_falls_through_to_defaults()
  withWorld("retail", function(w)
    w:stub("UnitName", { byArgs = { mouseover = { "Bob" } } })
    A.same({ _G.UnitName("target") }, { "", "" })
    A.eq(w.unscripted.UnitName, 1)
  end)
end

local function test_stub_function_and_returns_forms()
  withWorld("retail", function(w)
    w:stub("UnitName", function(unit)
      return unit .. "!"
    end)
    A.eq(_G.UnitName("player"), "player!")
    w:stub("UnitName", { returns = { "S" } })
    A.eq(_G.UnitName("player"), "S")
    A.eq(w.unscripted.UnitName, nil)
  end)
end

local function test_stub_unknown_name_errors()
  withWorld("retail", function(w)
    A.errors(function()
      w:stub("NotARealWowFunction", { returns = { 1 } })
    end, "NotARealWowFunction")
  end)
end

local function test_defaults_by_return_type()
  withWorld("retail", function(w)
    A.same({ _G.UnitName("player") }, { "", "" })
    A.eq(_G.UnitHealth("player"), 0)
    A.eq(select("#", _G.UnitHealth("player")), 1)
    A.eq(w.unscripted.UnitHealth, 2)
  end)
end

local function test_install_keeps_validation_and_stub_wins()
  withWorld("retail", function(w)
    local function impl()
      return "Impl"
    end
    A.eq(w:install("UnitName", impl, { gate = "api" }), true)
    A.eq(_G.UnitName("player"), "Impl")
    A.errors(function()
      w:run("addon", _G.UnitName, nil)
    end, "UnitName")
    w:stub("UnitName", { returns = { "S" } })
    A.eq(_G.UnitName("player"), "S")
  end)
end

return function()
  test_addon_context_validates_args()
  test_scenario_context_skips_validation()
  test_defaulted_arg_is_optional()
  test_addon_number_for_string_arg_is_coerced()
  test_calls_counted_through_lua_function_and_pcall()
  test_calls_not_counted_outside_addon_context()
  test_documented_name_validated_on_retail_only()
  test_stub_by_args_and_default()
  test_stub_by_args_joins_multiple_args()
  test_stub_unmatched_without_default_falls_through_to_defaults()
  test_stub_function_and_returns_forms()
  test_stub_unknown_name_errors()
  test_defaults_by_return_type()
  test_install_keeps_validation_and_stub_wins()
end
