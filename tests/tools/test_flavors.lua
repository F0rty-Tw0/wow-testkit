local A = require("assert")
local Flavors = require("tools.flavors")

local function test_list_names_the_five_flavors_in_order()
  A.same(Flavors.list, { "retail", "mists", "vanilla", "tbc", "forever" })
end

local function test_toc_version_of_packs_major_minor_patch()
  A.eq(Flavors.tocVersionOf("12.1.0.69933"), 120100)
  A.eq(Flavors.tocVersionOf("1.60.1.70205"), 16001)
  A.eq(Flavors.tocVersionOf("5.5.4.70032"), 50504)
  A.eq(Flavors.tocVersionOf("1.15.9.70003"), 11509)
  A.eq(Flavors.tocVersionOf("2.5.6.69795"), 20506)
end

local function test_major_minor_of_tells_forever_from_vanilla()
  A.eq(Flavors.majorMinorOf(16001), 160)
  A.eq(Flavors.majorMinorOf(11509), 115)
end

local function test_forever_is_mainline_and_vanilla_is_not()
  A.eq(Flavors.get("forever").gameTypes.mainline, true)
  A.eq(Flavors.get("vanilla").gameTypes.mainline, nil)
end

local function test_get_unknown_flavor_errors_listing_valid_ones()
  A.errors(function()
    Flavors.get("wrath")
  end, "retail")
end

local function test_get_returns_the_tbc_row()
  local tbc = Flavors.get("tbc")
  A.eq(tbc.name, "tbc")
  A.eq(tbc.branch, "classic_anniversary")
  A.eq(tbc.product, "wow_anniversary")
  A.same(tbc.interfaceKeys, { "Interface-TBC", "Interface-BCC" })
  A.same(tbc.tocSuffixes, { "_TBC", "-BCC", "_Classic" })
end

local function test_forever_product_is_unknown()
  A.eq(Flavors.get("forever").product, nil)
end

local function test_project_id_matches_wow_project_constant()
  A.eq(Flavors.get("mists").projectId, Flavors.WOW_PROJECT.WOW_PROJECT_MISTS_CLASSIC)
  A.eq(Flavors.get("tbc").projectId, Flavors.WOW_PROJECT.WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
  A.eq(Flavors.get("vanilla").projectId, Flavors.WOW_PROJECT.WOW_PROJECT_CLASSIC)
  A.eq(Flavors.get("forever").projectId, Flavors.WOW_PROJECT.WOW_PROJECT_MAINLINE)
end

local function test_defaults_come_from_built_in_builds()
  local retail = Flavors.get("retail")
  A.eq(retail.version, "12.1.0.69933")
  A.eq(retail.tocVersion, 120100)
  A.eq(retail.majorMinor, 1201)
end

-- Runs last: load mutates the module's rows.
local function test_load_replaces_version_fields()
  Flavors.load({ mists = { version = "5.5.5.71000", mirrorCommit = "abc" } })
  local mists = Flavors.get("mists")
  A.eq(mists.version, "5.5.5.71000")
  A.eq(mists.tocVersion, 50505)
  A.eq(mists.majorMinor, 505)
  A.eq(Flavors.get("retail").version, "12.1.0.69933", "flavors absent from the table keep their version")
end

return function()
  test_list_names_the_five_flavors_in_order()
  test_toc_version_of_packs_major_minor_patch()
  test_major_minor_of_tells_forever_from_vanilla()
  test_forever_is_mainline_and_vanilla_is_not()
  test_get_unknown_flavor_errors_listing_valid_ones()
  test_get_returns_the_tbc_row()
  test_forever_product_is_unknown()
  test_project_id_matches_wow_project_constant()
  test_defaults_come_from_built_in_builds()
  test_load_replaces_version_fields()
end
