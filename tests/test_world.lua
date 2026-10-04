-- World lifecycle, install gating, context stack, build info. Installed-function behavior: test_world_api.lua.
local A = require("assert")
local H = require("tests.helpers.world")
local World = require("world")

local withWorld, lookup = H.withWorld, H.lookup
local MYTHIC_SUMMARY = "C_PlayerInfo.GetPlayerMythicPlusRatingSummary"
-- In vanilla's globals.api, not documented in vanilla's manifest.
local DOTTED_PERMISSIVE = "C_AccountServices.IsAccountSaveEnabled"
local RETAIL_TOC_VERSION = 120100
local NEW_LIMIT_SECONDS = 5
-- SecureOnly in retail's manifest (checked 2026-10-04): Blizzard code only, never visible to addons.
local SECURE_ONLY = "C_CombatLogSecure.AddEventFilter"

-- Runs first, so the retail manifest load is included in the cold timing.
local function test_retail_world_new_is_fast()
  local started = os.clock()
  local w = World.new({ flavor = "retail" })
  local elapsed = os.clock() - started
  w:destroy()
  print(string.format('  World.new{ flavor = "retail" } (cold manifest): %.2f s', elapsed))
  started = os.clock()
  withWorld("retail", function() end)
  print(string.format("  World.new + destroy (warm manifest): %.2f s", os.clock() - started))
  A.truthy(elapsed < NEW_LIMIT_SECONDS, string.format("World.new took %.2f s", elapsed))
end

local function test_vanilla_lacks_mythic_plus_summary_retail_has_it()
  withWorld("vanilla", function()
    A.eq(lookup(MYTHIC_SUMMARY), nil)
  end)
  withWorld("retail", function()
    A.eq(type(lookup(MYTHIC_SUMMARY)), "function")
  end)
end

local function test_destroy_removes_api_and_restores_set_globals()
  _G.TK_PREEXISTING = "before"
  withWorld("retail", function(w)
    w:setGlobal("TK_PREEXISTING", "during")
    w:setGlobal("TK_NS.Deep.Value", 7)
    A.eq(_G.TK_PREEXISTING, "during")
    A.eq(lookup("TK_NS.Deep.Value"), 7)
  end)
  A.eq(rawget(_G, "UnitName"), nil)
  A.eq(rawget(_G, "TK_NS"), nil)
  A.eq(_G.TK_PREEXISTING, "before")
  _G.TK_PREEXISTING = nil
end

local function copyOf(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

local function test_destroy_restores_host_library_tables_exactly()
  local libraries = { string = string, table = table, math = math, os = os, coroutine = coroutine }
  local before = {}
  for name, lib in pairs(libraries) do
    before[name] = copyOf(lib)
  end
  withWorld("retail", function()
    for _, lib in pairs(libraries) do
      rawset(lib, "tkAdded", true)
    end
    rawset(string, "reverse", function() end)
  end)
  for name, lib in pairs(libraries) do
    A.same(copyOf(lib), before[name], name)
  end
end

local function test_destroy_restores_globals_metatable()
  local mt = {}
  setmetatable(_G, mt)
  withWorld("vanilla", function()
    setmetatable(_G, { __index = function() end })
  end)
  A.eq(getmetatable(_G), mt)
  setmetatable(_G, nil)
end

local function test_forever_library_extensions_restored_on_destroy()
  local realRequire = require
  withWorld("forever", function()
    A.eq(type(rawget(table, "create")), "function")
    A.eq(require, realRequire)
  end)
  A.eq(rawget(table, "create"), nil)
  A.eq(rawget(math, "round"), nil)
end

local function test_install_api_gate()
  withWorld("vanilla", function(w)
    A.eq(w:install(MYTHIC_SUMMARY, function() end, { gate = "api" }), false)
    A.eq(lookup(MYTHIC_SUMMARY), nil)
  end)
end

local function test_install_framexml_gate_uses_flavors()
  withWorld("vanilla", function(w)
    A.eq(w:install("TK_RetailOnly", 1, { gate = "framexml", flavors = { "retail" } }), false)
    A.eq(w:install("TK_Everywhere", 2, { gate = "framexml" }), true)
    A.eq(w:install("TK_NotFramexml", 3, { gate = "framexml", flavors = {} }), false)
    A.eq(_G.TK_Everywhere, 2)
    A.eq(rawget(_G, "TK_RetailOnly"), nil)
  end)
end

local function test_install_framexml_gate_uses_globals_framexml()
  withWorld("vanilla", function(w)
    local name = next(w.globals.framexml)
    A.eq(w:install(name, "fake", { gate = "framexml", flavors = {} }), true)
    A.eq(_G[name], "fake")
  end)
end

local function test_install_non_api_value_dotted()
  withWorld("retail", function(w)
    A.eq(w:install("TK_Fake.Thing", 5), true)
    A.eq(lookup("TK_Fake.Thing"), 5)
  end)
end

local function test_dotted_permissive_name_is_callable()
  withWorld("vanilla", function(w)
    A.eq(type(lookup(DOTTED_PERMISSIVE)), "function")
    w:run("addon", lookup(DOTTED_PERMISSIVE))
    A.eq(w.calls[DOTTED_PERMISSIVE], 1)
  end)
end

local function test_unknown_flavor_lists_valid_ones()
  A.errors(function()
    World.new({ flavor = "wrath" })
  end, "retail")
end

local function test_second_world_errors_until_destroyed()
  withWorld("vanilla", function()
    A.errors(function()
      World.new({ flavor = "vanilla" })
    end, "another world is active")
  end)
  withWorld("vanilla", function() end)
end

local function test_run_pops_context_on_error_and_rethrows_original()
  withWorld("vanilla", function(w)
    local thrown = {}
    local ok, err = pcall(w.run, w, "addon", function()
      error(thrown)
    end)
    A.eq(ok, false)
    A.eq(err, thrown)
    A.eq(w:context(), nil)
  end)
end

local function test_run_nests_contexts_and_returns_results()
  withWorld("vanilla", function(w)
    local a, b = w:run("blizzard", function()
      return w:run("addon", function()
        return w:context(), w:callerIsAddon()
      end)
    end)
    A.eq(a, "addon")
    A.eq(b, true)
    A.eq(w:context(), nil)
  end)
end

local function test_run_rejects_unknown_context()
  withWorld("vanilla", function(w)
    A.errors(function()
      w:run("player", function() end)
    end, "player")
  end)
end

local function test_secure_only_function_is_not_installed()
  withWorld("retail", function(w)
    A.eq(w.manifest.functions[SECURE_ONLY].secureOnly, true)
    A.eq(lookup(SECURE_ONLY), nil)
  end)
end

local function test_build_info_and_project_on_retail()
  withWorld("retail", function()
    A.same({ _G.GetBuildInfo() }, { "12.1.0", "69933", "Oct 1 2026", RETAIL_TOC_VERSION })
    A.eq(_G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE)
  end)
end

local function test_project_id_on_vanilla()
  withWorld("vanilla", function()
    A.eq(_G.WOW_PROJECT_ID, _G.WOW_PROJECT_CLASSIC)
  end)
end

local function test_enums_and_constants_installed()
  withWorld("retail", function(w)
    local enumName, enum = next(w.manifest.enums)
    local constName, const = next(w.manifest.constants)
    A.same(_G.Enum[enumName], enum)
    A.same(_G.Constants[constName], const)
  end)
end

return function()
  test_retail_world_new_is_fast()
  test_vanilla_lacks_mythic_plus_summary_retail_has_it()
  test_destroy_removes_api_and_restores_set_globals()
  test_destroy_restores_host_library_tables_exactly()
  test_destroy_restores_globals_metatable()
  test_forever_library_extensions_restored_on_destroy()
  test_install_api_gate()
  test_install_framexml_gate_uses_flavors()
  test_install_framexml_gate_uses_globals_framexml()
  test_install_non_api_value_dotted()
  test_dotted_permissive_name_is_callable()
  test_unknown_flavor_lists_valid_ones()
  test_second_world_errors_until_destroyed()
  test_run_pops_context_on_error_and_rethrows_original()
  test_run_nests_contexts_and_returns_results()
  test_run_rejects_unknown_context()
  test_secure_only_function_is_not_installed()
  test_build_info_and_project_on_retail()
  test_project_id_on_vanilla()
  test_enums_and_constants_installed()
end
