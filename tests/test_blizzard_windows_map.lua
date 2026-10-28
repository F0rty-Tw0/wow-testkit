-- The world map window (Task 12.4): the map opener sets the zone, loads the extract's map list and shows the window; the
-- window's tiles come from the C_Map art reads. Every extract is a kit-authored mini one (tests/helpers/blizzard.lua,
-- tests/helpers/windows.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local Render = require("render")
local W = require("tests.helpers.windows")

local MAP = { map = { addon = "Blizzard_MiniWorldMap", toggle = "MiniToggleWorldMap", frame = "MiniMapFrame" } }
local MAPS = {
  [13] = { name = "Kit Continent", mapType = 2, parentMapID = 947, flags = 0 },
  [37] = {
    name = "Kit Forest",
    mapType = 3,
    parentMapID = 13,
    flags = 0,
    layers = { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1, additionalZoomSteps = 0 } },
    tiles = { [1] = { 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012 } },
  },
}

-- The snapshot texture item whose file is the asset ref for fileID, or nil.
local function findTexture(snap, fileID)
  for _, item in ipairs(snap.items) do
    if item.kind == "texture" and item.file == "id:" .. fileID then
      return item
    end
  end
  return nil
end

local function test_world_map_window_draws_its_tiles()
  B.run(B.mini(), {
    targets = { "Blizzard_MiniBase" },
    before = function(s)
      s.w.windowSpecs = MAP
    end,
  }, function(s)
    s:openWindow("map", { mapID = 37, maps = MAPS })
    A.eq(_G.MiniMapFrame:IsShown(), true)
    A.eq(_G.MiniMapFrame.ticks, 1) -- the opener ran one frame of OnUpdate over the window
    local snap = Render.snapshot(s.w)
    A.truthy(findTexture(snap, 1001), "the first tile is a texture item with file id:1001")
    A.truthy(findTexture(snap, 1012), "the last tile is a texture item with file id:1012")
    s:closeWindow("map")
    A.eq(_G.MiniMapFrame:IsShown(), false)
  end)
end

local DB2 = {
  uimap = "return { [1429] = { ID = 1429, Name_lang = 'Kit Forest', Type = 3, ParentUiMapID = 0, Flags = 0 } }",
}

local function test_map_opener_sets_the_zone_and_position()
  W.scenario("retail", { db2 = DB2 }, function(s)
    s:openWindow("map", { mapID = 1429, position = { x = 0.4, y = 0.6 } })
    A.same({ _G.C_Map.GetBestMapForUnit("player"), _G.C_Map.GetMapInfo(1429).name }, { 1429, "Kit Forest" })
    A.same({ _G.C_Map.GetPlayerMapPosition(1429, "player"):GetXY() }, { 0.4, 0.6 })
  end)
end

local function test_map_opener_picks_the_flavors_map_id()
  W.scenario("tbc", {}, function(s)
    s:openWindow("map", { mapIDs = { retail = 37, tbc = 1429 } })
    A.eq(_G.C_Map.GetBestMapForUnit("player"), 1429)
  end)
  W.scenario("retail", {}, function(s)
    s:openWindow("map", { mapIDs = { tbc = 1429 } }) -- no id for the flavor: the zone stays as it was
    A.eq(_G.C_Map.GetBestMapForUnit("player"), nil)
  end)
end

-- MapCanvasMixin:GetPinTemplateType (blizzard_mapcanvas.lua:315) asks the engine for the type of a pin's XML template; with
-- no answer the quest blob pin was a plain Frame and its OnLoad (SetFillTexture) aborted the world map's OnLoad.
local PIN = {
  blizzard_minipin = {
    toc = "## Interface: 120100\nMiniPin.xml\n",
    files = {
      ["minipin.xml"] = '<Ui xmlns="http://www.blizzard.com/wow/ui/"><QuestPOIFrame name="MiniBlobTemplate" virtual="true"/></Ui>',
    },
  },
}
local function test_template_info_answers_the_type_of_an_xml_template_assumed()
  B.run(B.mini(PIN), { targets = { "Blizzard_MiniBase", "Blizzard_MiniPin" } }, function(s)
    A.same(_G.C_XMLUtil.GetTemplateInfo("MiniBlobTemplate"), { type = "QuestPOIFrame", width = 0, height = 0 })
    A.eq(_G.CreateFrame("Frame", nil, nil, "MiniBlobTemplate").SetFillTexture, nil) -- CreateFrame's own type is unchanged
    s.w:setMock({ templateInfo = { MiniBlobTemplate = { type = "Frame" } } })
    A.eq(_G.C_XMLUtil.GetTemplateInfo("MiniBlobTemplate").type, "Frame") -- the scenario's answer wins
  end)
end

-- ScrollBoxLinearView.lua:193 compares a row template's height from GetTemplateInfo with 0; with no size no ScrollBox list
-- built a row. The size comes through the inherits chain in order, the template's own <Size> last, per axis.
local SIZED = {
  blizzard_minirow = {
    toc = "## Interface: 120100\nMiniRow.xml\n",
    files = {
      ["minirow.xml"] = '<Ui xmlns="http://www.blizzard.com/wow/ui/">'
        .. '<Frame name="MiniRowBase" virtual="true"><Size x="100" y="20"/></Frame>'
        .. '<Button name="MiniRow" inherits="MiniRowBase" virtual="true"><Size><AbsDimension y="24"/></Size></Button>'
        .. '<Frame name="MiniRowWide" virtual="true"><Size x="300"/></Frame>'
        .. '<Frame name="MiniRowBoth" inherits="MiniRow, MiniRowWide" virtual="true"/>'
        .. "</Ui>",
    },
  },
}
local function test_template_info_answers_the_size_through_the_inherits_chain()
  B.run(B.mini(SIZED), { targets = { "Blizzard_MiniBase", "Blizzard_MiniRow" } }, function()
    local info = _G.C_XMLUtil.GetTemplateInfo
    A.same(info("MiniRowBase"), { type = "Frame", width = 100, height = 20 })
    A.same(info("MiniRow"), { type = "Button", width = 100, height = 24, inherits = "MiniRowBase" })
    A.same(info("MiniRowBoth"), { type = "Frame", width = 300, height = 24, inherits = "MiniRow, MiniRowWide" })
    A.same({ _G.CreateFrame("Frame", nil, nil, "MiniRowBoth"):GetSize() }, { 300, 24 }) -- the size a built frame gets
  end)
end

-- ShowUIPanel (uiparentpanelmanager.lua:205) asks StoreFrame_IsShown() before it places a panel; the real StoreFrame never
-- loads here (its secure file stops at Enum.VasServiceType, which no installed data lists), so the layer stands one in.
local STORE = {
  blizzard_ministore = {
    toc = "## Interface: 120100\nMiniStore.lua\n",
    files = { ["ministore.lua"] = 'function StoreFrame_IsShown() return StoreFrame:GetAttribute("isshown") end' },
  },
}
local function test_window_open_stands_in_a_closed_store_frame_assumed()
  B.run(B.mini(STORE), {
    targets = { "Blizzard_MiniBase", "Blizzard_MiniStore" },
    before = function(s)
      s.w.windowSpecs = MAP
    end,
  }, function(s)
    A.eq(_G.StoreFrame, nil)
    s:openWindow("map", { mapID = 37, maps = MAPS })
    A.same({ _G.StoreFrame:IsShown(), _G.StoreFrame_IsShown() }, { false, nil })
  end)
end

-- source: assumed (row BU11) the tbc Blizzard_MapCanvas.xml:3 names a sibling addon's file by its game-root path
-- (..\..\..\Interface\AddOns\<Addon>\<file>); the extract keeps addons side by side, so the layer reads it from there.
local GAME_ROOT_PATH = {
  blizzard_minipath = {
    toc = "## Interface: 120100\nMiniPath.xml\n",
    files = {
      ["minipath.xml"] = '<Ui xmlns="http://www.blizzard.com/wow/ui/"><Script file="..\\..\\..\\Interface\\AddOns\\Blizzard_MiniPath\\Part.lua"/></Ui>',
      ["part.lua"] = "MiniPathLoaded = true",
    },
  },
}
local function test_xml_script_by_game_root_path_reads_the_sibling_file_assumed()
  B.run(B.mini(GAME_ROOT_PATH), { targets = { "Blizzard_MiniBase", "Blizzard_MiniPath" } }, function()
    A.eq(_G.MiniPathLoaded, true)
  end)
end

return function()
  test_xml_script_by_game_root_path_reads_the_sibling_file_assumed()
  test_window_open_stands_in_a_closed_store_frame_assumed()
  test_template_info_answers_the_type_of_an_xml_template_assumed()
  test_template_info_answers_the_size_through_the_inherits_chain()
  test_world_map_window_draws_its_tiles()
  test_map_opener_sets_the_zone_and_position()
  test_map_opener_picks_the_flavors_map_id()
end
