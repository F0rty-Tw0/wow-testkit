-- The kit consumers of a client extract: real strings, atlas info, SetAtlas sizing and glyph widths. w.client is the
-- only switch, so with none the world is the kit's own.
local A = require("assert")
local FrameXML = require("framexml.fakes")
local H = require("tests.helpers.client")
local Measure = require("ui.measure")
local Tmp = require("tests.helpers.tmp")
local World = require("world")

local ATLAS = 'return { ["mini-atlas"] = { name = "Mini-Atlas", file = 111, width = 20, height = 10, left = 0, right = 0.5, top = 0, bottom = 1 } }'

-- Runs fn(w) in a retail world with stage-1 FrameXML over a mini extract holding files; files nil is no extract.
local function withClient(files, fn)
  local extract = files and H.extract(Tmp.dir("consumers"), "retail", "1", files)
  local w = World.new({ flavor = "retail", client = extract })
  local ok, err = pcall(function()
    FrameXML.installStage1(w)
    fn(w)
  end)
  w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function test_world_keeps_the_client_it_was_given()
  local w = World.new({ flavor = "retail", client = { dir = "x" } })
  local kept = w.client
  w:destroy()
  A.eq(kept.dir, "x")
end

local function test_real_strings_replace_the_kit_values()
  withClient({ ["strings/enUS.lua"] = 'return { TOOLTIP_UNIT_LEVEL = "Lv %s", ONLY_REAL = "r" }' }, function()
    A.eq(_G.TOOLTIP_UNIT_LEVEL, "Lv %s")
    A.eq(_G.ONLY_REAL, "r")
    A.eq(_G.FACTION_HORDE, "Horde") -- untouched kit value stays
  end)
end

local function test_extract_without_strings_or_atlas_leaves_the_kit_values()
  withClient({}, function()
    A.eq(_G.TOOLTIP_UNIT_LEVEL, "Level %s")
    A.eq(_G.C_Texture.GetAtlasInfo("mini-atlas"), nil)
  end)
end

local function test_no_extract_changes_nothing() -- Review Focus 5
  withClient(nil, function(w)
    A.eq(_G.TOOLTIP_UNIT_LEVEL, "Level %s")
    local get = _G.C_Texture and _G.C_Texture.GetAtlasInfo -- the API stub may exist; it must answer nothing
    A.eq(get and get("mini-atlas"), nil)
    A.eq(w.measure, nil)
    A.eq(Measure.width(w, "Fonts\\FRIZQT__.TTF", 10, "", "abc"), 15)
  end)
end

local function test_atlas_info_answers_the_extract_entry()
  withClient({ ["atlas.lua"] = ATLAS }, function()
    local info = _G.C_Texture.GetAtlasInfo("Mini-Atlas") -- lookup is case-insensitive
    A.same(info, {
      width = 20,
      height = 10,
      leftTexCoord = 0,
      rightTexCoord = 0.5,
      topTexCoord = 0,
      bottomTexCoord = 1,
      file = 111,
      tilesHorizontally = false,
      tilesVertically = false,
    })
    A.eq(_G.C_Texture.GetAtlasInfo("nope"), nil)
  end)
end

local function test_set_atlas_with_use_atlas_size_sizes_the_texture()
  withClient({ ["atlas.lua"] = ATLAS }, function()
    local t = _G.CreateFrame("Frame"):CreateTexture()
    t:SetAtlas("Mini-Atlas", true)
    A.eq(t:GetWidth(), 20)
    A.eq(t:GetHeight(), 10)
    A.eq(t:GetAtlas(), "Mini-Atlas")
  end)
end

local function test_set_atlas_without_use_atlas_size_keeps_the_size()
  withClient({ ["atlas.lua"] = ATLAS }, function()
    local t = _G.CreateFrame("Frame"):CreateTexture()
    t:SetSize(5, 6)
    t:SetAtlas("Mini-Atlas")
    A.eq(t:GetWidth(), 5)
    A.eq(t:GetHeight(), 6)
  end)
end

local function test_set_atlas_with_use_atlas_size_and_no_extract_keeps_the_size()
  withClient(nil, function()
    local t = _G.CreateFrame("Frame"):CreateTexture()
    t:SetSize(5, 6)
    t:SetAtlas("Mini-Atlas", true)
    A.eq(t:GetWidth(), 5)
    A.eq(t:GetAtlas(), "Mini-Atlas")
  end)
end

local function test_set_atlas_with_an_unknown_atlas_keeps_the_size()
  withClient({ ["atlas.lua"] = ATLAS }, function()
    local t = _G.CreateFrame("Frame"):CreateTexture()
    t:SetSize(5, 6)
    t:SetAtlas("nope", true)
    A.eq(t:GetWidth(), 5)
  end)
end

local function test_glyph_tables_measure_text_through_the_world()
  local table = "return { upm = 1000, notdef = 500, advance = { [65] = 700 }, kern = {} }"
  withClient({ ["fonts/glyphs/frizqt__.ttf.lua"] = table }, function(w)
    A.eq(Measure.width(w, "Fonts\\FRIZQT__.TTF", 10, "", "AA"), 14)
  end)
end

return function()
  test_world_keeps_the_client_it_was_given()
  test_real_strings_replace_the_kit_values()
  test_extract_without_strings_or_atlas_leaves_the_kit_values()
  test_no_extract_changes_nothing()
  test_atlas_info_answers_the_extract_entry()
  test_set_atlas_with_use_atlas_size_sizes_the_texture()
  test_set_atlas_without_use_atlas_size_keeps_the_size()
  test_set_atlas_with_use_atlas_size_and_no_extract_keeps_the_size()
  test_set_atlas_with_an_unknown_atlas_keeps_the_size()
  test_glyph_tables_measure_text_through_the_world()
end
