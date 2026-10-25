-- Client: finds the newest extract under the testkit home and maps a kind and key to a file inside it.
local A = require("assert")
local Client = require("client")
local H = require("tests.helpers.client")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local function test_find_returns_nil_without_an_extract() -- Review Focus 5
  A.eq(Client.find("retail", H.getenv(Tmp.dir("noext"))), nil)
  A.eq(Client.find("retail", function() end), nil) -- no resolvable home: nil, no error
end

local function test_find_picks_the_highest_numeric_build()
  local root = Tmp.dir("find")
  H.extract(root, "retail", "9000", {})
  H.extract(root, "retail", "70575", {})
  A.eq(Client.find("retail", H.getenv(root)).build, "70575") -- 70575 > 9000 numerically, not by string
end

local function test_find_reports_the_directory_and_flavor()
  local root = Tmp.dir("finddir")
  H.extract(root, "retail", "1", {})
  local found = Client.find("retail", H.getenv(root))
  A.eq(found.dir, root .. "/client/retail/1")
  A.eq(found.flavor, "retail")
  A.eq(found.locales[1], "enUS")
end

local function test_find_ignores_other_flavors_and_stray_names()
  local root = Tmp.dir("findother")
  H.extract(root, "vanilla", "5", {})
  fs.mkdirp(root .. "/client/retail/notes")
  A.eq(Client.find("retail", H.getenv(root)), nil)
end

local function test_find_returns_nil_for_a_manifest_that_does_not_load()
  local root = Tmp.dir("findbad")
  fs.mkdirp(root .. "/client/retail/7")
  fs.writeFile(root .. "/client/retail/7/manifest.lua", "return {")
  A.eq(Client.find("retail", H.getenv(root)), nil)
  fs.writeFile(root .. "/client/retail/7/manifest.lua", "return 5")
  A.eq(Client.find("retail", H.getenv(root)), nil)
end

local function test_path_maps_kinds_and_lowercases_keys()
  local ex = H.extract(Tmp.dir("path"), "retail", "1", { ["art/interface/buttons/white8x8.png"] = "x", ["art/by-id/136235.png"] = "x" })
  A.eq(Client.path(ex, "art", "Interface\\Buttons\\WHITE8X8"), ex.dir .. "/art/interface/buttons/white8x8.png")
  A.eq(Client.path(ex, "art", 136235), ex.dir .. "/art/by-id/136235.png")
  A.eq(Client.path(ex, "art", "Interface\\Nope"), nil)
end

local function test_path_art_ignores_an_image_extension()
  local ex = H.extract(Tmp.dir("pathext"), "retail", "1", { ["art/interface/icons/foo.png"] = "x" })
  A.eq(Client.path(ex, "art", "Interface\\Icons\\Foo.blp"), ex.dir .. "/art/interface/icons/foo.png")
end

local function test_path_font_and_glyphs_reduce_to_the_file_name()
  local ex = H.extract(Tmp.dir("pathfont"), "retail", "1", { ["fonts/frizqt__.ttf"] = "x", ["fonts/glyphs/frizqt__.ttf.lua"] = "x" })
  A.eq(Client.path(ex, "font", "Fonts\\FRIZQT__.TTF"), ex.dir .. "/fonts/frizqt__.ttf")
  A.eq(Client.path(ex, "glyphs", "Fonts\\FRIZQT__.TTF"), ex.dir .. "/fonts/glyphs/frizqt__.ttf.lua")
  A.eq(Client.path(ex, "font", "Fonts\\Other.ttf"), nil)
end

local function test_path_maps_code_atlas_strings_and_db2()
  local ex = H.extract(Tmp.dir("pathrest"), "retail", "1", {
    ["code/addons/blizzard_foo/foo.lua"] = "x",
    ["art/atlas/128-redbutton-up.png"] = "x",
    ["strings/enUS.lua"] = "x",
    ["db2/spell.lua"] = "x",
  })
  A.eq(Client.path(ex, "code", "Addons\\Blizzard_Foo\\Foo.lua"), ex.dir .. "/code/addons/blizzard_foo/foo.lua")
  A.eq(Client.path(ex, "atlas", "128-RedButton-UP"), ex.dir .. "/art/atlas/128-redbutton-up.png")
  A.eq(Client.path(ex, "strings", "enUS"), ex.dir .. "/strings/enUS.lua")
  A.eq(Client.path(ex, "db2", "Spell"), ex.dir .. "/db2/spell.lua")
end

local function test_path_rejects_an_unknown_kind()
  local ex = H.extract(Tmp.dir("pathkind"), "retail", "1", {})
  A.errors(function()
    Client.path(ex, "movie", "x")
  end, "unknown kind")
end

local function test_strings_default_to_the_first_locale()
  local ex =
    H.extract(Tmp.dir("strings"), "retail", "1", { ["strings/enUS.lua"] = 'return { A = "a" }', ["strings/deDE.lua"] = 'return { A = "b" }' })
  A.eq(Client.strings(ex).A, "a")
  A.eq(Client.strings(ex, "deDE").A, "b")
  A.eq(Client.strings(ex, "frFR"), nil)
end

local function test_atlas_lookup_is_case_insensitive()
  local row = '{ name = "Mini-Atlas", file = 111, width = 20, height = 10, left = 0, right = 0.5, top = 0, bottom = 1 }'
  local ex = H.extract(Tmp.dir("atlas"), "retail", "1", { ["atlas.lua"] = 'return { ["mini-atlas"] = ' .. row .. " }" })
  A.eq(Client.atlas(ex, "Mini-ATLAS").file, 111)
  A.eq(Client.atlas(ex, "nope"), nil)
  A.eq(Client.atlas(H.extract(Tmp.dir("noatlas"), "retail", "1", {}), "mini-atlas"), nil)
end

return function()
  test_find_returns_nil_without_an_extract()
  test_find_picks_the_highest_numeric_build()
  test_find_reports_the_directory_and_flavor()
  test_find_ignores_other_flavors_and_stray_names()
  test_find_returns_nil_for_a_manifest_that_does_not_load()
  test_path_maps_kinds_and_lowercases_keys()
  test_path_art_ignores_an_image_extension()
  test_path_font_and_glyphs_reduce_to_the_file_name()
  test_path_maps_code_atlas_strings_and_db2()
  test_path_rejects_an_unknown_kind()
  test_strings_default_to_the_first_locale()
  test_atlas_lookup_is_case_insensitive()
end
