-- Checks the committed, generated manifests under api/ (tools/generate.lua output on the fetched mirror).
local A = require("assert")
local Flavors = require("tools.flavors")
local Manifest = require("manifest")
local fs = require("fs")

local MYTHIC_SUMMARY = "C_PlayerInfo.GetPlayerMythicPlusRatingSummary"
local RAW_DOC_MARKER = "APIDocumentation:AddDocumentationTable"
local LOAD_TARGET_SECONDS = 2
local LOAD_LIMIT_SECONDS = 5
local MIN_FUNCTIONS = 1000

local SOURCE = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local ROOT = SOURCE:gsub("/?tests/test_manifests%.lua$", "")
local API_DIR = (ROOT == "" and "." or ROOT) .. "/api"

local function count(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

local function walkFiles(dir, out)
  for _, name in ipairs(fs.list(dir)) do
    local path = dir .. "/" .. name
    if fs.isdir(path) then
      walkFiles(path, out)
    else
      out[#out + 1] = path
    end
  end
  return out
end

-- Runs first: later tests hit Manifest's per-flavor cache.
local function test_retail_loads_within_time_limit()
  local started = os.clock()
  Manifest.load("retail")
  local elapsed = os.clock() - started
  print(string.format('  Manifest.load("retail"): %.2f s (target < %d s)', elapsed, LOAD_TARGET_SECONDS))
  A.truthy(elapsed < LOAD_LIMIT_SECONDS, string.format("retail load took %.2f s", elapsed))
end

local function test_retail_has_mythic_plus_rating_summary()
  local manifest = Manifest.load("retail")
  A.truthy(manifest.functions[MYTHIC_SUMMARY])
end

local function test_vanilla_lacks_mythic_plus_rating_summary()
  local manifest, globals = Manifest.load("vanilla")
  A.eq(manifest.functions[MYTHIC_SUMMARY], nil, "vanilla manifest")
  A.eq(globals.api[MYTHIC_SUMMARY], nil, "vanilla globals.api")
end

-- Per-function Namespace: "" in C_RestrictedActions is a global, "table" in C_TableUtil is the table library.
local function test_every_flavor_keys_functions_by_their_own_namespace()
  for _, flavor in ipairs(Flavors.list) do
    local functions = Manifest.load(flavor).functions
    A.truthy(functions.InCombatLockdown, flavor .. " InCombatLockdown")
    A.truthy(functions["table.count"], flavor .. " table.count")
    A.eq(functions["C_RestrictedActions.InCombatLockdown"], nil, flavor)
  end
end

-- Classic Era's and TBC's docs carry C_AuctionHouse, but their clients have none of it (Ketho's GlobalAPI).
local function test_only_clients_with_the_modern_auction_house_document_it()
  local GET_BIDS = "C_AuctionHouse.GetBids"
  A.eq(Manifest.load("vanilla").functions[GET_BIDS], nil, "vanilla")
  A.eq(Manifest.load("tbc").functions[GET_BIDS], nil, "tbc")
  A.truthy(Manifest.load("mists").functions[GET_BIDS], "mists")
end

local function test_retail_issecretvalue_args_allowed_when_untainted()
  local fn = Manifest.load("retail").functions.issecretvalue
  A.truthy(fn, "issecretvalue in retail manifest")
  A.eq(fn.secret.args, "AllowedWhenUntainted")
end

local function test_versions_retail_is_12_1()
  local versions = require("api.versions")
  A.eq(versions.retail.version:sub(1, 5), "12.1.")
end

local function test_no_raw_doc_files_under_api()
  local files = walkFiles(API_DIR, {})
  A.truthy(#files > 0, "files under " .. API_DIR)
  for _, path in ipairs(files) do
    A.eq(string.find(fs.readFile(path), RAW_DOC_MARKER, 1, true), nil, path)
  end
end

local function test_every_flavor_loads_with_over_1000_functions()
  for _, flavor in ipairs(Flavors.list) do
    local manifest = Manifest.load(flavor)
    local n = count(manifest.functions)
    A.truthy(n > MIN_FUNCTIONS, flavor .. " has " .. n .. " functions")
  end
end

return function()
  test_retail_loads_within_time_limit()
  test_retail_has_mythic_plus_rating_summary()
  test_vanilla_lacks_mythic_plus_rating_summary()
  test_every_flavor_keys_functions_by_their_own_namespace()
  test_only_clients_with_the_modern_auction_house_document_it()
  test_retail_issecretvalue_args_allowed_when_untainted()
  test_versions_retail_is_12_1()
  test_no_raw_doc_files_under_api()
  test_every_flavor_loads_with_over_1000_functions()
end
