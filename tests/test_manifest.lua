local A = require("assert")
local Tmp = require("tests.helpers.tmp")
local Flavors = require("tools.flavors")
local Manifest = require("manifest")
local fs = require("fs")

local function tempDir()
  return Tmp.dir("manifest")
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

-- The defaults in tools/flavors.lua equal api/versions.lua today, so the rows are made stale first: only
-- requiring manifest.lua can put the generated versions back.
local function test_loading_the_kit_applies_api_versions_to_every_flavor()
  local versions = require("api.versions")
  for _, flavor in ipairs(Flavors.list) do
    local row = Flavors.get(flavor)
    row.version, row.tocVersion = "0.0.1.1", 1
  end
  package.loaded.manifest = nil
  local ok, err = pcall(require, "manifest")
  package.loaded.manifest = Manifest
  assert(ok, err)
  for _, flavor in ipairs(Flavors.list) do
    local row = Flavors.get(flavor)
    A.eq(row.version, versions[flavor].version, flavor .. " version")
    A.eq(row.tocVersion, Flavors.tocVersionOf(versions[flavor].version), flavor .. " tocVersion")
  end
end

-- source: row G23, Blizzard's retail code registers TRIAL_STATUS_UPDATE; no API doc lists it.
local function test_retail_knows_events_blizzard_code_registers()
  A.same(Manifest.load("retail").events.TRIAL_STATUS_UPDATE, {})
  A.eq(Manifest.load("vanilla").events.TRIAL_STATUS_UPDATE, nil)
end

-- source: row G25, the tbc extract's Blizzard_MoneyFrame registers TRIAL_STATUS_UPDATE on load (classic/moneyframe.lua:17, :39).
local function test_tbc_knows_the_event_its_money_frame_registers()
  A.same(Manifest.load("tbc").events.TRIAL_STATUS_UPDATE, {})
  A.eq(Manifest.load("mists").events.TRIAL_STATUS_UPDATE, nil)
end

-- source: row G31, the forever extract's Blizzard_MoneyFrame registers TRIAL_STATUS_UPDATE on load (mainline/moneyframe.lua:36).
local function test_forever_knows_the_event_its_money_frame_registers()
  A.same(Manifest.load("forever").events.TRIAL_STATUS_UPDATE, {})
end

-- source: row G49, the tbc and forever extracts' PlayerFrame registers PLAYTIME_CHANGED on load (classic/playerframe.lua:56,
-- mainline/playerframe.lua); no API doc lists it.
local function test_player_frame_playtime_event_is_known() -- G49
  A.same(Manifest.load("tbc").events.PLAYTIME_CHANGED, {})
  A.same(Manifest.load("forever").events.PLAYTIME_CHANGED, {})
end

-- source: row G56, the tbc and forever extracts' shop, kiosk, expansion and glue code registers these at load
-- (forever mainline/mainmenubarmicrobuttons.lua:1859 STORE_STATUS_CHANGED, smartnavigation.lua:167 KIOSK_SESSION_EXPIRED,
-- eventutil.lua:12 FRAMES_LOADED; tbc classic/productchoice.lua:6, classic/alertframes.lua:422); no API doc lists them.
local function test_shop_and_kiosk_events_are_known() -- G56
  local both = {
    "KIOSK_SESSION_EXPIRED",
    "STORE_OPEN_SIMPLE_CHECKOUT",
    "STORE_PRODUCTS_UPDATED",
    "STORE_PURCHASE_ERROR",
    "STORE_STATUS_CHANGED",
    "UPDATE_EXPANSION_LEVEL",
    "FRAMES_LOADED",
  }
  for _, event in ipairs(both) do
    A.same(Manifest.load("tbc").events[event], {}, "tbc " .. event)
    A.same(Manifest.load("forever").events[event], {}, "forever " .. event)
  end
  for _, event in ipairs({ "PRODUCT_CHOICE_UPDATE", "PRODUCT_ASSIGN_TO_TARGET_FAILED", "STORE_PRODUCT_DELIVERED" }) do
    A.same(Manifest.load("tbc").events[event], {}, "tbc " .. event)
  end
end

-- Blizzard_Shared_StoreUISecure.lua (forever 70862) registers these in three OnLoads; none is documented, so the first
-- unknown one raised and stopped each OnLoad. (G74)
local function test_forever_knows_the_store_window_events()
  local events = Manifest.load("forever").events
  -- stylua: ignore
  for _, event in ipairs({ "STORE_PURCHASE_LIST_UPDATED", "PRODUCT_DISTRIBUTIONS_UPDATED", "STORE_CONFIRM_PURCHASE",
    "STORE_CHARACTER_LIST_RECEIVED", "STORE_GUILD_MASTER_INFO_RECEIVED", "DYNAMIC_BUNDLE_PRICE_UPDATED" }) do
    A.same(events[event], {}, event)
  end
end

return function()
  test_shop_and_kiosk_events_are_known()
  test_forever_knows_the_store_window_events()
  test_player_frame_playtime_event_is_known()
  test_load_merges_functions_from_every_file()
  test_load_merges_other_sections()
  test_load_copies_index_fields()
  test_load_returns_globals()
  test_load_caches_per_flavor_and_root()
  test_load_unknown_flavor_errors_listing_valid_flavors()
  test_loading_the_kit_applies_api_versions_to_every_flavor()
  test_retail_knows_events_blizzard_code_registers()
  test_tbc_knows_the_event_its_money_frame_registers()
  test_forever_knows_the_event_its_money_frame_registers()
end
