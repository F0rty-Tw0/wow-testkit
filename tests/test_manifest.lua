local A = require("assert")
local Flavors = require("tools.flavors")
local Manifest = require("manifest")
local fs = require("fs")

math.randomseed(os.time())

local function tempDir()
  local base = (os.getenv("TEMP") or "/tmp"):gsub("\\", "/")
  return base .. "/wow-testkit-manifest-" .. os.time() .. "-" .. math.random(1, 1000000)
end

-- A tiny split manifest for the made-up flavor "zz": an index, two file modules and the globals.
local function writeTinyManifest()
  local root = tempDir()
  local dir = root .. "/api/zz"
  fs.mkdirp(dir)
  fs.writeFile(dir .. "/init.lua", 'return { flavor = "zz", version = "1.2.3.4", files = { "A", "B" } }\n')
  fs.writeFile(dir .. "/A.lua", "return { functions = { FnA = {} }, enums = { E = { X = 1 } } }\n")
  fs.writeFile(dir .. "/B.lua", "return { functions = { FnB = {} }, events = { EV = {} } }\n")
  fs.writeFile(dir .. "/globals.lua", "return { api = { GetTime = true } }\n")
  return root
end

local root = writeTinyManifest()
local manifest, globals = Manifest.load("zz", { root = root })

local function test_load_merges_functions_from_every_file()
  A.same(manifest.functions, { FnA = {}, FnB = {} })
end

local function test_load_merges_other_sections()
  A.same(manifest.enums, { E = { X = 1 } })
  A.same(manifest.events, { EV = {} })
  A.same(manifest.structs, {})
end

local function test_load_copies_index_fields()
  A.eq(manifest.flavor, "zz")
  A.eq(manifest.version, "1.2.3.4")
end

local function test_load_returns_globals()
  A.same(globals, { api = { GetTime = true } })
end

local function test_load_caches_per_flavor_and_root()
  local again = Manifest.load("zz", { root = root })
  A.eq(again, manifest)
end

local function test_load_unknown_flavor_errors_listing_valid_flavors()
  A.errors(function()
    Manifest.load("nope")
  end, "retail")
end

local function test_loading_the_kit_applies_api_versions_to_every_flavor()
  local versions = require("api.versions")
  for _, flavor in ipairs(Flavors.list) do
    local row = Flavors.get(flavor)
    A.eq(row.version, versions[flavor].version, flavor .. " version")
    A.eq(row.tocVersion, Flavors.tocVersionOf(versions[flavor].version), flavor .. " tocVersion")
  end
end

return function()
  test_load_merges_functions_from_every_file()
  test_load_merges_other_sections()
  test_load_copies_index_fields()
  test_load_returns_globals()
  test_load_caches_per_flavor_and_root()
  test_load_unknown_flavor_errors_listing_valid_flavors()
  test_loading_the_kit_applies_api_versions_to_every_flavor()
end
