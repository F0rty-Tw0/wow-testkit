-- The kit consumers of a client extract: real strings, atlas info and glyph widths (SetAtlas sizing is in
-- tests/ui/test_behaviour_texture.lua). w.client is the only switch, so with none the world is the kit's own.
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

local function test_glyph_tables_measure_text_through_the_world()
  local table = "return { upm = 1000, notdef = 500, advance = { [65] = 700 }, kern = {} }"
  withClient({ ["fonts/glyphs/frizqt__.ttf.lua"] = table }, function(w)
    A.eq(Measure.width(w, "Fonts\\FRIZQT__.TTF", 10, "", "AA"), 14)
  end)
end

-- api.lua as tools/client_api.lua writes it: enums and constants from the extract's own API docs.
local API = "return { enums = { ApiOnlyEnum = { A = 1 }, ItemQuality = { Poor = 99, ApiOnlyField = 42 }, Bad = 5 },"
  .. " constants = { ApiOnlyConsts = { X = 7 } }, events = { API_ONLY_EVENT = true } }"

-- source: row G57, forever 70862 voicechatdocumentation.lua:919 documents VOICE_CHAT_ACTIVE_VOICE_PROVIDER_CHANGED,
-- which api/forever (an older doc set) lacks; blizzard_chatframe/shared/voicechattranscriptionbutton.lua:4 registers it.
local function test_api_overlay_makes_the_extract_events_known() -- G57
  withClient({ ["api.lua"] = API }, function(w)
    require("game").install(w) -- C_EventUtils.IsEventValid (game/clientapi.lua)
    local frame = _G.CreateFrame("Frame")
    frame:RegisterEvent("API_ONLY_EVENT") -- raised "unknown event" before
    A.eq(_G.C_EventUtils.IsEventValid("API_ONLY_EVENT"), true)
    A.eq(_G.C_EventUtils.IsEventValid("NOPE_EVENT"), false)
    A.eq(w.manifest.events.API_ONLY_EVENT, nil) -- the manifest stays the kit's
  end)
  withClient({}, function()
    A.eq(pcall(_G.CreateFrame("Frame").RegisterEvent, _G.CreateFrame("Frame"), "API_ONLY_EVENT"), false)
  end)
end

local BOOL_RETURN = "{ returns = { { name = 'shown', type = 'bool', lua = 'boolean', nilable = false } } }"
local FUNCTIONS_API = "return { functions = {"
  .. (" ['C_ExternalEventURL.ApiOnlyFn'] = %s,"):format(BOOL_RETURN)
  .. (" ['C_NoSuchNamespace.Fn'] = %s,"):format(BOOL_RETURN)
  .. " ['C_ExternalEventURL.SecureFn'] = { secureOnly = true },"
  .. (" ApiOnlyGlobal = %s, ['C_ExternalEventURL.Bad'] = 5 } }"):format(BOOL_RETURN)

-- source: row G75, forever 70862 externaleventurldocumentation.lua documents C_ExternalEventURL.CanShow, which
-- api/forever lacks; blizzard_minimap/shared/externaleventurlminimapbutton.lua:77 called it and raised at load.
local function test_api_overlay_stubs_documented_functions_the_kit_lacks() -- G75
  withClient({ ["api.lua"] = FUNCTIONS_API }, function(w)
    A.eq(_G.C_ExternalEventURL.ApiOnlyFn(), false) -- the signature's default
    A.eq(w.manifest.functions["C_ExternalEventURL.ApiOnlyFn"], nil) -- the manifest stays the kit's
    A.eq(_G.C_NoSuchNamespace, nil) -- a namespace the flavor lacks stays absent
    A.eq(_G.C_ExternalEventURL.SecureFn, nil)
    A.eq(_G.ApiOnlyGlobal, nil)
    A.eq(_G.C_ExternalEventURL.Bad, nil)
  end)
  withClient({}, function()
    A.eq(_G.C_ExternalEventURL.ApiOnlyFn, nil)
  end)
end

local function test_api_overlay_adds_a_missing_enum_table()
  withClient({ ["api.lua"] = API }, function()
    A.eq(_G.Enum.ApiOnlyEnum.A, 1)
  end)
end

local function test_api_overlay_adds_missing_fields_and_keeps_kit_values()
  withClient({ ["api.lua"] = API }, function(w)
    A.eq(w.manifest.enums.ItemQuality.ApiOnlyField, nil) -- the manifest stays the kit's
    A.eq(_G.Enum.ItemQuality.Poor, 0) -- the kit value wins
    A.eq(_G.Enum.ItemQuality.ApiOnlyField, 42)
  end)
end

local function test_api_overlay_fills_constants_too()
  withClient({ ["api.lua"] = API }, function()
    A.eq(_G.Constants.ApiOnlyConsts.X, 7)
  end)
end

local function test_api_overlay_skips_a_non_table_entry()
  withClient({ ["api.lua"] = API }, function()
    A.eq(_G.Enum.Bad, nil)
  end)
end

local function test_extract_without_api_file_changes_no_enum()
  withClient({}, function()
    A.eq(_G.Enum.ApiOnlyEnum, nil)
  end)
end

local function test_broken_api_file_changes_no_enum()
  withClient({ ["api.lua"] = "return 1" }, function()
    A.eq(_G.Enum.ApiOnlyEnum, nil)
    A.eq(_G.Enum.ItemQuality.Poor, 0)
  end)
end

return function()
  test_api_overlay_makes_the_extract_events_known()
  test_api_overlay_stubs_documented_functions_the_kit_lacks()
  test_api_overlay_adds_a_missing_enum_table()
  test_api_overlay_adds_missing_fields_and_keeps_kit_values()
  test_api_overlay_fills_constants_too()
  test_api_overlay_skips_a_non_table_entry()
  test_extract_without_api_file_changes_no_enum()
  test_broken_api_file_changes_no_enum()
  test_world_keeps_the_client_it_was_given()
  test_real_strings_replace_the_kit_values()
  test_extract_without_strings_or_atlas_leaves_the_kit_values()
  test_no_extract_changes_nothing()
  test_atlas_info_answers_the_extract_entry()
  test_glyph_tables_measure_text_through_the_world()
end
