-- Generate.build's function keys: function namespaces, and namespaces Ketho never lists.
local A = require("assert")
local Generate = require("tools.generate")
local GenerateIo = require("tools.generate_io")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local KETHO_DIR = TEST_DIR .. "/../fixtures/ketho"
local META = { flavor = "retail", branch = "live", version = "12.1.0.69933", mirrorCommit = "abc123" }
local ketho = GenerateIo.loadKetho(KETHO_DIR)

local function systemEntry(file, fn, namespace)
  return { file = file, doc = { Name = file, Type = "System", Namespace = namespace, Functions = { fn } } }
end

local function keysOf(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  return keys
end

-- The fixture Ketho lists, with GlobalAPI replaced: global API names, then Lua library names (as Ketho splits them).
local function kethoListing(apiNames, luaNames)
  local listing = {}
  for key, value in pairs(ketho) do
    listing[key] = value
  end
  listing.GlobalAPI = { apiNames, luaNames }
  return listing
end

local NAMESPACED_KETHO = kethoListing({ "C_StringUtil.TrimWhitespace" }, { "table.wipe" })

local function functionKeys(fn, namespace)
  local one = { systemEntry("ADocumentation.lua", fn, namespace) }
  return keysOf(Generate.build(one, NAMESPACED_KETHO, META).manifest.functions)
end

local function buildOne(fn, namespace)
  return Generate.build({ systemEntry("ADocumentation.lua", fn, namespace) }, ketho, META)
end

-- Classic Era's docs carry C_AuctionHouse, yet its client (Ketho's GlobalAPI) has no C_AuctionHouse function.
local function test_function_in_a_namespace_ketho_never_lists_is_dropped_and_counted()
  local built = buildOne({ Name = "GetBids", Type = "Function" }, "C_AuctionHouse")
  A.same(built.manifest.functions, {})
  A.same(built.report.dropped, { C_AuctionHouse = 1 })
end

local function test_function_missing_from_a_listed_namespace_is_kept()
  local built = buildOne({ Name = "DoOtherThing", Type = "Function" }, "C_SecureSystem")
  A.truthy(built.manifest.functions["C_SecureSystem.DoOtherThing"], "kept")
  A.same(built.report.dropped, {})
end

-- Ketho's lists come from an addon environment, where secure-only functions never show.
local function test_secure_only_function_in_an_unlisted_namespace_is_kept()
  local built = buildOne({ Name = "AcceptTrade", Type = "Function", Environment = "SecureOnly" }, "C_SecureTransfer")
  A.truthy(built.manifest.functions["C_SecureTransfer.AcceptTrade"], "kept")
end

-- Real Ketho lists table.count and string.trim only in its LuaAPI list (GlobalAPI[2]), never in GlobalAPI[1].
local function test_namespace_listed_only_among_lua_names_is_kept()
  local one = { systemEntry("ADocumentation.lua", { Name = "count", Type = "Function", Namespace = "table" }) }
  local built = Generate.build(one, kethoListing({}, { "table.count" }), META)
  A.truthy(built.manifest.functions["table.count"], "kept")
  A.same(built.report.dropped, {})
end

local function test_global_function_missing_from_ketho_is_kept()
  A.truthy(buildOne({ Name = "ToggleCollision", Type = "Function" }).manifest.functions.ToggleCollision, "kept")
end

-- LuaTableUtilDocumentation.lua: `count` in system C_TableUtil carries Namespace = "table".
local function test_function_namespace_replaces_system_namespace_in_key()
  A.same(functionKeys({ Name = "count", Type = "Function", Namespace = "table" }, "C_TableUtil"), { "table.count" })
end

-- RestrictedActionsDocumentation.lua: InCombatLockdown in C_RestrictedActions carries Namespace = "".
local function test_empty_function_namespace_makes_a_global_key()
  A.same(functionKeys({ Name = "InCombatLockdown", Type = "Function", Namespace = "" }, "C_RestrictedActions"), {
    "InCombatLockdown",
  })
end

-- LocalizationDocumentation.lua: a system without Namespace whose function carries Namespace = "C_StringUtil".
local function test_function_namespace_applies_in_a_system_without_one()
  A.same(functionKeys({ Name = "GetDefaultAbbreviationBreakpoints", Type = "Function", Namespace = "C_StringUtil" }), {
    "C_StringUtil.GetDefaultAbbreviationBreakpoints",
  })
end

return function()
  test_function_namespace_replaces_system_namespace_in_key()
  test_empty_function_namespace_makes_a_global_key()
  test_function_namespace_applies_in_a_system_without_one()
  test_function_in_a_namespace_ketho_never_lists_is_dropped_and_counted()
  test_function_missing_from_a_listed_namespace_is_kept()
  test_secure_only_function_in_an_unlisted_namespace_is_kept()
  test_namespace_listed_only_among_lua_names_is_kept()
  test_global_function_missing_from_ketho_is_kept()
end
